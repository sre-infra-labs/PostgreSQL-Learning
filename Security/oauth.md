# OAuth 2.0 Authentication for PostgreSQL 18

Goal: let users log in to PostgreSQL with a bearer token issued by an OpenID Connect (OIDC) identity provider, using the built-in `oauth` method in `pg_hba.conf`.

How it fits together:

1. The client (`psql`/libpq) asks the identity provider for a token. By default libpq uses the device authorization flow: it prints a URL and a code, and the user signs in in a browser.
2. The client sends the token to the server.
3. The server loads a **validator module**, which checks the token (signature, issuer, expiry, scope) and returns the authenticated identity.
4. PostgreSQL compares that identity with the requested role, or maps it with `pg_ident.conf`.

PostgreSQL ships no validator. You must provide one (section 3).

## Placeholders

| Placeholder | Example | Meaning |
|---|---|---|
| `auth.example.com` | `keycloak.corp.local:8443` | Identity provider host (HTTPS) |
| `corp` | realm `corp` | Realm / tenant name at the provider |
| `pg-server` | | Resource (API) client that represents the PostgreSQL server |
| `psql-cli` | | Public client used by `psql` for the device flow |
| `10.0.0.0/24` | | Client subnet allowed to use OAuth |
| `pgdb01` | | PostgreSQL server host |

## 0. Decisions to make first

| Decision | Recommended default | Alternatives |
|---|---|---|
| Identity provider | **Keycloak**, federating the AD users from `ldap.md` | Microsoft Entra ID, Okta, any OIDC provider with a device flow |
| Validator | **`kc_validator`** (Keycloak-specific, experimental) | Write your own JWT validator (section 3b) |
| Client flow | Device authorization grant (libpq default) | Custom hook via `PQsetAuthDataHook` |

Important: **AD DS alone cannot issue OAuth tokens.** Active Directory speaks LDAP/Kerberos, not OIDC. You need an OIDC provider in front of AD. Keycloak can read the same AD accounts through LDAP federation, so the `ldap.md` setup carries over.

## 1. Prerequisites checklist

### 1.1 PostgreSQL 18 built with libcurl

The `oauth` method and libpq's device flow require PostgreSQL 18 or later. libpq's built-in OAuth flow needs libcurl 7.61.0 or later, which is enabled at build time with `--with-libcurl` (Meson: `-Dlibcurl=enabled`).

Check on the PostgreSQL host:

```bash
psql -tAc "SHOW server_version;"
pg_config --version
pg_config --configure | tr ' ' '\n' | grep -i curl     # expect --with-libcurl
curl-config --version 2>/dev/null || dpkg -l | grep libcurl
```

Ubuntu/Debian PGDG packages for PostgreSQL 18 are built with `--with-libcurl`. Verified on this machine: PostgreSQL 18.6 with `--with-libcurl`, libcurl 8.18.0.

If you build from source, install the dependencies first:

```bash
# Debian / Ubuntu
sudo apt install -y libcurl4-openssl-dev libssl-dev libpq-dev postgresql-server-dev-18

# RHEL / Rocky / Alma
sudo dnf install -y libcurl-devel openssl-devel
```

### 1.2 Identity provider reachable over HTTPS

- The issuer URL must be **HTTPS**. Both the server and clients must be able to reach it.
- The discovery document must load:

```bash
curl -s https://auth.example.com/realms/corp/.well-known/openid-configuration | jq '.issuer, .token_endpoint, .device_authorization_endpoint, .jwks_uri'
```

Expected: all four values print. `device_authorization_endpoint` is required for libpq's built-in flow. If it is `null`, enable the device grant on the client (step 2.3).

- The `issuer` value printed here must match the `issuer=` value you put in `pg_hba.conf` **exactly** (case, trailing slash, and formatting).

### 1.3 TLS trust

- The provider's certificate must be trusted by the **PostgreSQL server** (the validator fetches keys and calls the token endpoint) and by **clients** (libpq fetches the discovery document).
- For a private CA, install the CA on the PostgreSQL host:

```bash
sudo cp corp-root-ca.pem /usr/local/share/ca-certificates/corp-root-ca.crt
sudo update-ca-certificates
```

- Clients with a private CA can point libpq at it with `PGOAUTHCAFILE=/path/to/corp-root-ca.pem`. Do not use `PGOAUTHDEBUG=UNSAFE` outside local development (see section 6).

### 1.4 Clock synchronization

Token `exp`/`nbf` checks fail if clocks drift. Make sure the PostgreSQL host, the identity provider, and clients use NTP:

```bash
timedatectl status | grep -E 'synchronized|NTP'
```

### 1.5 Firewall

| From | To | Port | Purpose |
|---|---|---|---|
| Clients | Identity provider | 443 (or 8443) | Device flow, discovery |
| PostgreSQL host | Identity provider | 443 (or 8443) | Token and key fetch (validator) |
| Clients | PostgreSQL | 5432 | Database connections |

### 1.6 Role naming

The token's identity claim (for example `preferred_username`) must equal the PostgreSQL role name, or you need a `map=` entry. Pick one claim now and keep it consistent. This doc uses `preferred_username`, which is the AD `sAMAccountName` when Keycloak federates AD.

## 2. Configure the identity provider (Keycloak)

These steps use the Keycloak admin console. Names match the placeholders above.

### 2.1 Realm and AD federation

1. Create realm `corp`.
2. **User federation > Add provider > LDAP** and point it at `dc01.corp.local` using the `svc-pg-ldap` account from `ldap.md`. Use LDAPS (`ldaps://dc01.corp.local:636`) with the AD CA trusted by Keycloak's Java truststore.
3. Set **Username LDAP attribute** to `sAMAccountName`, and sync the `pg_users` group members.

### 2.2 Resource client for the PostgreSQL server

1. **Clients > Create client**: Client ID `pg-server`. Client authentication **off** (public), or **on** if you use the kc validator (it needs a client secret for token introspection; check its docs).
2. Under **Client scopes**, add an audience mapper so access tokens carry `aud=pg-server`.
3. Add a mapper that puts the username into the access token:
   - Mapper type: **User Property**, property `username`, token claim name `preferred_username`, add to access token: **on**.

### 2.3 Public client for psql (device flow)

1. **Clients > Create client**: Client ID `psql-cli`.
2. **Client authentication: off** (public client).
3. **Advanced settings > OAuth 2.0 Device Authorization Grant Enabled: on**.
4. Set the default scope to include `pg-server` audience (add the `pg-server` client scope as a default scope).

### 2.4 Verify the discovery document and device grant

```bash
curl -s https://auth.example.com/realms/corp/.well-known/openid-configuration | jq -r '.device_authorization_endpoint'

# Request a device code for psql-cli
curl -s -X POST https://auth.example.com/realms/corp/protocol/openid-connect/auth/device \
  -d client_id=psql-cli -d scope=openid | jq
```

Expected: JSON with `device_code`, `user_code`, `verification_uri`. If you get `unauthorized_client`, the device grant is off on `psql-cli`.

### 2.5 Database access rule (only for kc_validator)

The `kc_validator` decides access from Keycloak Authorization Services. Each database role needs a matching scope name, and a permission named `<resource_name>#<scope>` on the resource. Skip this if you use a plain JWT validator.

- Create a Keycloak resource for the server (for example `appdb`) on `pg-server`.
- Create one scope per PostgreSQL role (for example `alice_role`), and a permission `appdb#alice_role` that grants it to the users who may log in as that role.

## 3. Install a validator module

PostgreSQL does not provide validators. Use one of these options.

### 3a. Keycloak validator (`kc_validator`, experimental)

Project: https://github.com/cloudnative-pg/postgres-keycloak-oauth-validator
Requirements: PostgreSQL 18+, Meson, libcurl. The project is marked **experimental**. Review its code and pin a version before using it.

```bash
git clone https://github.com/cloudnative-pg/postgres-keycloak-oauth-validator.git
cd postgres-keycloak-oauth-validator
meson setup build
meson compile -C build
```

Install the resulting shared library into PostgreSQL's library directory. Check the install step in that project's docs; the expected result is:

```bash
ls "$(pg_config --pkglibdir)" | grep -i kc_validator
```

Expected: `kc_validator.so`.

### 3b. Write your own validator (sketch)

The validator must:

- Export `_PG_oauth_validator_module_init()` returning a `const OAuthValidatorCallbacks *` with `magic = PG_OAUTH_VALIDATOR_MAGIC` and a non-NULL `validate_cb`.
- In `validate_cb(state, token, role, result)`: verify the JWT signature against the provider's `jwks_uri` keys, check `iss`, `aud`, `exp`/`nbf`, and the required scope. On success set `result->authorized = true` and `result->authn_id` (palloc'd) to the username claim. On any failure set `result->authorized = false` and return `true`. Return `false` only on internal error.
- Fail closed. A validator that accepts a bad token is worse than no authentication.

Build it with PGXS or Meson against `postgresql-server-dev-18` and install it to `pg_config --pkglibdir`.

## 4. Configure the server

### 4.1 postgresql.conf

```
oauth_validator_libraries = 'kc_validator'
```

Validator-specific settings (`kc.*`) go in the same file. For the Keycloak validator, the settings listed by its project are:

```
kc.token_endpoint = 'https://auth.example.com/realms/corp/protocol/openid-connect/token'
kc.audience = 'pg-server'
kc.resource_name = 'appdb'
kc.client_id = 'pg-server'
kc.http_timeout_ms = 2000
kc.expected_issuer = 'https://auth.example.com/realms/corp'
log_min_messages = 'debug1'   # during testing only
```

Notes:

- `oauth_validator_libraries` is set only in `postgresql.conf`. The default is empty, which refuses all OAuth connections.
- If you list more than one library, every `oauth` line in `pg_hba.conf` must set `validator=`.
- Check whether a restart or reload is needed:

```sql
SELECT name, context FROM pg_settings WHERE name IN ('oauth_validator_libraries');
```

Then reload (`context = sighup`) or restart (`postmaster`):

```bash
sudo systemctl reload postgresql     # or: sudo systemctl restart postgresql
```

### 4.2 pg_hba.conf

Add the `oauth` rule above the broader `scram-sha-256` rules (first match wins). Use `hostssl` so tokens are never sent over plain TCP.

```
# TYPE    DATABASE  USER  ADDRESS       METHOD  OPTIONS
hostssl   all       all   10.0.0.0/24   oauth   issuer="https://auth.example.com/realms/corp" scope="openid pg-server" validator="kc_validator" delegate_ident_mapping=1
```

Option reference (from the PostgreSQL 18 docs):

| Option | Required | Meaning |
|---|---|---|
| `issuer` | Yes | HTTPS issuer identifier, or a URL to the discovery document. Must match the token's `iss` exactly. |
| `scope` | Yes | Space-separated scopes the client must have. Validator decides what is valid. |
| `validator` | When more than one library is listed | Must match a name in `oauth_validator_libraries`. |
| `map` | No | Maps provider user names to roles via `pg_ident.conf`. |
| `delegate_ident_mapping` | No | `1` lets the validator decide role access, skipping `pg_ident.conf`. Cannot be combined with `map`. |

Choose one of these:

- **Direct match** (no `map`): the identity claim must equal the role name. Simplest. Requires `delegate_ident_mapping` off and no `map=`.
- **Delegated** (`delegate_ident_mapping=1`): the validator is responsible for checking that the token may log in as `role`. Use with `kc_validator`, which does this via Keycloak permissions. Do not combine with `map`.

Reload after editing `pg_hba.conf`:

```sql
SELECT pg_reload_conf();
SELECT line_number, type, database, user_name, address, auth_method, options FROM pg_hba_file_rules;
```

### 4.3 Create matching roles

Every OAuth login still needs a PostgreSQL role:

```sql
CREATE ROLE alice LOGIN;
GRANT CONNECT ON DATABASE appdb TO alice;
```

For `kc_validator`, the role name must match the Keycloak scope name from step 2.5.

## 5. Client setup (psql / libpq)

Connect with the device flow:

```bash
psql "host=pgdb01.corp.local port=5432 dbname=appdb user=alice sslmode=verify-full \
      require_auth=oauth oauth_issuer=https://auth.example.com/realms/corp oauth_client_id=psql-cli"
```

What happens:

1. libpq contacts the issuer and gets a device code.
2. It prints something like `Visit https://auth.example.com/realms/corp/device and enter the code: ABCD-EFGH`.
3. The user signs in (with AD credentials through Keycloak) and approves the request.
4. libpq sends the token; the server validates it and logs the user in.

Optional libpq parameters:

| Parameter | Use |
|---|---|
| `oauth_scope` | Overrides the scopes the server requests. Set explicitly when the issuer is a `/.well-known/` URL. |
| `oauth_client_secret` | Only for confidential clients. |
| `require_auth=oauth` | Refuse the connection unless the server asks for OAuth. Prevents downgrade to passwords. |

Set `PGOAUTHCAFILE` if the issuer uses a private CA.

Note: the built-in device flow is not supported on Windows. Windows clients need a custom flow using the `PQsetAuthDataHook` API.

## 6. Test

Positive test (from a client):

```bash
psql "host=pgdb01.corp.local dbname=appdb user=alice sslmode=verify-full require_auth=oauth oauth_issuer=https://auth.example.com/realms/corp oauth_client_id=psql-cli" \
  -c "SELECT current_user, session_user;"
```

Expected: `current_user = alice`.

Check the session used OAuth:

```sql
SELECT usename, client_addr, ssl FROM pg_stat_ssl JOIN pg_stat_activity USING (pid) WHERE pid = pg_backend_pid();
```

Negative tests (each must fail):

```bash
# Wrong issuer string (extra trailing slash) -> issuer mismatch
psql "host=pgdb01.corp.local dbname=appdb user=alice sslmode=verify-full require_auth=oauth oauth_issuer=https://auth.example.com/realms/corp/ oauth_client_id=psql-cli"

# A user without the Keycloak permission for alice_role (kc_validator) -> rejected
psql "host=pgdb01.corp.local dbname=appdb user=bob sslmode=verify-full require_auth=oauth oauth_issuer=https://auth.example.com/realms/corp oauth_client_id=psql-cli"

# Plain TCP (no SSL) -> no matching pg_hba.conf entry
psql "host=pgdb01.corp.local dbname=appdb user=alice sslmode=disable require_auth=oauth oauth_issuer=https://auth.example.com/realms/corp oauth_client_id=psql-cli"
```

Read the server log for the reason of each rejection:

```bash
sudo tail -n 100 /var/log/postgresql/postgresql-18-main.log
```

Debugging the client only (never on production hosts, never share the output): `PGOAUTHDEBUG=UNSAFE` allows plain HTTP, replaces the CA list with `PGOAUTHCAFILE`, and prints tokens and secrets to stderr.

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `OAuth connections are refused` / empty validator | `oauth_validator_libraries` is empty | Set it in `postgresql.conf` and reload or restart |
| `could not load library "kc_validator"` | Library not in `pkglibdir`, or built for another PostgreSQL major version | Rebuild against `pg_config` of PostgreSQL 18 and reinstall |
| `issuer mismatch` | Trailing slash or case difference between `pg_hba.conf` `issuer` and discovery `issuer` | Copy the exact `issuer` value from the discovery document |
| `device_authorization_endpoint` is null / `unauthorized_client` | Device grant disabled on `psql-cli` | Enable "OAuth 2.0 Device Authorization Grant" (step 2.3) |
| Token rejected: audience | `pg-server` audience mapper missing | Add the audience mapper (step 2.2) |
| Token rejected: expired / not yet valid | Clock drift | Fix NTP on the DB host and the provider |
| `certificate verify failed` | Private CA not trusted by server or client | Section 1.3; `PGOAUTHCAFILE` on clients |
| `no pg_hba.conf entry` | Client not using SSL, or subnet not covered | Use `hostssl` and `sslmode=verify-full` |
| `role "alice" does not exist` | Role not created | Step 4.3 |
| Browser/code prompt does not appear on Windows | Built-in device flow not supported on Windows | Use a custom flow through `PQsetAuthDataHook` |

## 8. Hardening

- Use `hostssl` and `sslmode=verify-full` everywhere. Never accept tokens over plain TCP.
- Use `require_auth=oauth` in client connection strings for OAuth-only accounts, so a server cannot silently fall back to password auth.
- Keep token lifetimes short (for example 5–15 minutes) and enable refresh in the provider.
- Limit the `pg_hba.conf` `ADDRESS` column; avoid `0.0.0.0/0`, which the kc_validator example uses only for illustration.
- Keep `log_min_messages` at `warning` in production. `debug1` and `kc.log_body` log more detail, and `kc.log_body` may log tokens.
- Review and pin any third-party validator. A bug in a validator can admit unauthorized users.
- Keep at least one non-OAuth superuser path (for example local peer authentication) for recovery.

## 9. Checklist

- [ ] PostgreSQL 18+ with `--with-libcurl` (`pg_config --configure`)
- [ ] OIDC provider reachable over HTTPS; discovery document loads and includes `device_authorization_endpoint`
- [ ] Keycloak realm `corp` federating AD users (see `ldap.md`)
- [ ] `pg-server` resource client with `aud` mapper and `preferred_username` claim
- [ ] `psql-cli` public client with device grant enabled
- [ ] Provider CA trusted on the DB host and clients
- [ ] NTP synchronized on DB host, provider, and clients
- [ ] Validator built against PostgreSQL 18 and installed in `pkglibdir`
- [ ] `oauth_validator_libraries` set in `postgresql.conf`; server reloaded or restarted
- [ ] `pg_hba.conf` `hostssl ... oauth` rule placed above broader rules; `pg_hba_file_rules` shows no error
- [ ] PostgreSQL roles created for each OAuth user
- [ ] Positive login test passes; negative tests fail as expected
- [ ] Log level and token logging reviewed for production
