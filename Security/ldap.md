# LDAP Authentication on Top of Windows Active Directory (KVM / SQLMonitor)

Goal: let users log in to PostgreSQL with their Active Directory credentials. Active Directory already speaks LDAP, so the work is:

1. Make sure AD DS and DNS are healthy on the Windows KVM guest.
2. Open the LDAP ports between the PostgreSQL host and the domain controller.
3. Create a low-privilege bind account (and optionally a group that controls who may log in).
4. Enable LDAPS (TLS) with a certificate from AD CS. Do not send passwords over plain LDAP.
5. Verify LDAP queries from the Linux host with `ldapsearch`.
6. Point `pg_hba.conf` at the domain controller, reload, and test.

## Placeholders

Replace these everywhere below.

| Placeholder | Example | Meaning |
|---|---|---|
| `corp.local` | `corp.local` | AD DNS domain |
| `DC=corp,DC=local` | | Base DN |
| `dc01.corp.local` | `dc01.corp.local` | Domain controller FQDN (SQLMonitor VM) |
| `10.0.0.10` | | DC IP address on the KVM network |
| `10.0.0.20` | | PostgreSQL host IP |
| `10.0.0.0/24` | | Client subnet allowed to log in |
| `svc-pg-ldap` | | Bind account used by PostgreSQL |
| `pg_users` | | AD group allowed to log in to PostgreSQL |

## 0. Assumptions

- The Windows guest on the KVM host is the domain controller (`SQLMonitor`) and runs AD DS and DNS.
- PostgreSQL runs on a Linux host (Debian/Ubuntu shown; RHEL equivalents noted where they differ). If PostgreSQL runs on the Windows VM itself, skip the Linux-only steps (sections 4's `/etc/ldap/ldap.conf` and `update-ca-certificates`, 5, 8's `chown`/`chmod`, and 11); the `pg_hba.conf` rules are the same.
- Both VMs are on the same KVM virtual network, or the PostgreSQL host can route to the DC.

## 1. Verify Active Directory on the DC

Run in an elevated PowerShell on `dc01`:

```powershell
Get-Service NTDS, DNS, Netlogon | Format-Table Name, Status
Get-ADDomain | Select-Object Name, DNSRoot, DistinguishedName
Get-ADDomainController -Discover -DomainName corp.local
dcdiag /q
```

All three services must be `Running`. `dcdiag /q` should print no errors.

Confirm the domain DNS resolves from the Linux host:

```bash
getent hosts dc01.corp.local
dig +short _ldap._tcp.corp.local SRV
```

If the SRV lookup fails, set the PostgreSQL host's DNS server to the DC IP (`10.0.0.10`), or use the IP address in `ldapserver`. Note that Kerberos and TLS certificate name checks need the FQDN, so DNS is preferred.

## 2. Network and firewall

KVM host (optional, only if the VMs are on separate libvirt networks):

```bash
sudo virsh net-list --all
sudo virsh net-dumpxml default   # confirm both VMs are on this network
```

Windows firewall on the DC: LDAP and LDAPS must be reachable from the PostgreSQL host. AD DS usually opens these by default, but verify:

```powershell
Get-NetFirewallRule -DisplayGroup "Active Directory Domain Services" |
  Where-Object Enabled -eq 'True' | Select-Object DisplayName
```

From the PostgreSQL host:

```bash
nc -zv dc01.corp.local 389    # LDAP (StartTLS)
nc -zv dc01.corp.local 636    # LDAPS
```

Ports used:

| Port | Protocol | Use |
|---|---|---|
| 389 | TCP | LDAP, or LDAP with StartTLS |
| 636 | TCP | LDAPS (TLS from the first byte) |
| 53 | TCP/UDP | DNS |
| 3268 / 3269 | TCP | Global Catalog (only if you need forest-wide lookup) |

## 3. Create the bind account and the login group

PostgreSQL needs one account to search the directory for the user trying to log in. Give it read-only access and no admin rights.

```powershell
$pw = Read-Host -AsSecureString "Password for svc-pg-ldap"

New-ADUser -Name "svc-pg-ldap" -SamAccountName "svc-pg-ldap" `
  -UserPrincipalName "svc-pg-ldap@corp.local" `
  -Path "OU=Service Accounts,DC=corp,DC=local" `
  -AccountPassword $pw -Enabled $true -PasswordNeverExpires $true `
  -CannotChangePassword $true

New-ADGroup -Name "pg_users" -GroupScope Global -GroupCategory Security `
  -Path "OU=Groups,DC=corp,DC=local"

# Example login user
New-ADUser -Name "Alice Test" -SamAccountName "alice" `
  -UserPrincipalName "alice@corp.local" -Path "OU=Users,DC=corp,DC=local" `
  -AccountPassword (Read-Host -AsSecureString "Password for alice") -Enabled $true
Add-ADGroupMember -Identity pg_users -Members alice
```

Notes:

- `svc-pg-ldap` does not need membership in any privileged group. Default "Authenticated Users" read access to user objects is enough.
- Do not use Domain Admin for the bind account.
- Store the password only in `pg_hba.conf` (protected, see section 8) or a secrets manager.

## 4. Enable LDAPS with AD CS

LDAPS needs a certificate on the DC that the PostgreSQL host trusts. The simplest route is AD Certificate Services (AD CS) as an enterprise root CA.

On the DC:

```powershell
Install-WindowsFeature AD-Certificate-Services -IncludeManagementTools
Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CaCommonName "corp-root-ca" -Force
```

Domain controllers auto-enroll a "Domain Controller" or "Kerberos Authentication" certificate once the CA exists. Check:

```powershell
certutil -pulse
Get-ChildItem Cert:\LocalMachine\My |
  Where-Object { $_.EnhancedKeyUsageList.FriendlyName -contains 'Server Authentication' } |
  Select-Object Subject, NotAfter
```

Export the CA certificate so Linux can trust it:

```powershell
certutil -ca.cert C:\Temp\corp-root-ca.cer
certutil -encode C:\Temp\corp-root-ca.cer C:\Temp\corp-root-ca.pem
```

Copy `corp-root-ca.pem` to the PostgreSQL host (`scp`, or a shared folder), then on Linux:

```bash
sudo cp corp-root-ca.pem /usr/local/share/ca-certificates/corp-root-ca.crt
sudo update-ca-certificates
```

For the OpenLDAP client library (which PostgreSQL uses), also set the CA in `/etc/ldap/ldap.conf` (RHEL: `/etc/openldap/ldap.conf`):

```
BASE   DC=corp,DC=local
URI    ldaps://dc01.corp.local
TLS_CACERT /usr/local/share/ca-certificates/corp-root-ca.crt
TLS_REQCERT demand
```

Verify the TLS handshake. The output must show `Verify return code: 0 (ok)` and the certificate subject must match `dc01.corp.local`:

```bash
openssl s_client -connect dc01.corp.local:636 -CAfile /usr/local/share/ca-certificates/corp-root-ca.crt </dev/null 2>/dev/null | grep -E 'subject=|Verify return code'
```

If you see `certificate verify failed` or a name mismatch, the DC certificate is missing the FQDN in its SAN or the CA is not trusted. Fix that before continuing.

## 5. Install the LDAP client tools (Linux)

```bash
# Debian / Ubuntu
sudo apt install -y ldap-utils

# RHEL / Rocky / Alma
sudo dnf install -y openldap-clients
```

## 6. Test LDAP queries from the PostgreSQL host

Bind as the service account and look up a user. Quote the DN and password carefully; the `$` and `!` characters need care in shells.

```bash
export BIND_DN='CN=svc-pg-ldap,OU=Service Accounts,DC=corp,DC=local'
read -rs -p "svc-pg-ldap password: " BIND_PW; echo

# Plain LDAP with StartTLS (port 389)
ldapsearch -H ldap://dc01.corp.local -ZZ -x -D "$BIND_DN" -w "$BIND_PW" \
  -b 'DC=corp,DC=local' '(sAMAccountName=alice)' dn sAMAccountName memberOf

# LDAPS (port 636)
ldapsearch -H ldaps://dc01.corp.local -x -D "$BIND_DN" -w "$BIND_PW" \
  -b 'DC=corp,DC=local' '(sAMAccountName=alice)' dn sAMAccountName memberOf
```

Expected: one entry for `alice` with `memberOf` containing `CN=pg_users,...`.

Verify that a user can bind with their own password (this is exactly what PostgreSQL will do):

```bash
ldapwhoami -H ldaps://dc01.corp.local -x -D "alice@corp.local" -W
```

Expected: `dn:CN=Alice Test,OU=Users,DC=corp,DC=local`. An `ldap_bind: Invalid credentials (49)` error means wrong password, locked account, or disabled account (AD returns the sub-code in the message, e.g. `data 775` = locked, `data 533` = disabled).

## 7. Configure PostgreSQL `pg_hba.conf`

Find the active file:

```sql
SHOW hba_file;
```

PostgreSQL 10+ can also show parsed rules, which is useful for checking syntax:

```sql
SELECT line_number, type, database, user_name, address, auth_method, options
FROM pg_hba_file_rules;
```

Two modes are available. Use **search+bind** (recommended for AD). It allows login by `sAMAccountName` and can restrict logins to a group.

### Option A: search+bind (recommended)

Add lines to `pg_hba.conf`. Put them above any broader `host ... scram-sha-256` rule, because the first match wins.

```
# TYPE    DATABASE  USER  ADDRESS        METHOD  OPTIONS
hostssl   all       all   10.0.0.0/24    ldap    ldapserver="dc01.corp.local" ldapscheme=ldaps ldapport=636 ldapbasedn="DC=corp,DC=local" ldapbinddn="CN=svc-pg-ldap,OU=Service Accounts,DC=corp,DC=local" ldapbindpasswd="REPLACE_ME" ldapsearchfilter="(&(sAMAccountName=$username)(memberOf=CN=pg_users,OU=Groups,DC=corp,DC=local))"
```

If you do not need the group restriction, use `ldapsearchattribute` instead:

```
hostssl   all       all   10.0.0.0/24    ldap    ldapserver="dc01.corp.local" ldapscheme=ldaps ldapport=636 ldapbasedn="DC=corp,DC=local" ldapbinddn="CN=svc-pg-ldap,OU=Service Accounts,DC=corp,DC=local" ldapbindpasswd="REPLACE_ME" ldapsearchattribute="sAMAccountName"
```

To use StartTLS on port 389 instead of LDAPS, replace `ldapscheme=ldaps ldapport=636` with `ldaptls=1 ldapport=389`. Do not combine `ldaptls=1` with `ldapscheme=ldaps`.

### Option B: simple bind (UPN, no service account)

PostgreSQL builds the bind DN from the username and a suffix, then binds as the user. Users then log in with the UPN form `alice@corp.local` or with the suffix stripped by the client.

```
hostssl   all       all   10.0.0.0/24    ldap    ldapserver="dc01.corp.local" ldapscheme=ldaps ldapport=636 ldapsuffix="@corp.local"
```

Simple bind cannot filter by group, so any valid AD account can log in to any database that has a matching role. Prefer Option A for production.

### Important details

- `hostssl` requires SSL on the client-to-PostgreSQL connection, so the user's password is not sent in clear text to the database. Clients must use `sslmode=require` or stronger. The PostgreSQL-to-DC leg is protected separately by `ldapscheme=ldaps` (or `ldaptls=1`).
- `ldapbindpasswd` is stored in clear text inside `pg_hba.conf`. See section 8 for protecting it.
- Multiple DCs can be listed in `ldapserver="dc01.corp.local dc02.corp.local"` for failover.
- PostgreSQL authenticates the user only. Authorization is still the PostgreSQL role, so create one per AD user (section 7b).

### 7b. Create matching PostgreSQL roles

LDAP does not create roles. Each AD login must exist as a PostgreSQL role with the same name as `sAMAccountName`:

```sql
CREATE ROLE alice LOGIN;
GRANT CONNECT ON DATABASE postgres TO alice;
```

Use the existing role and privilege scripts in this folder (`users-roles.sql`, `create-user-read-write.sql`) as a template for grants.

### Reload

```sql
SELECT pg_reload_conf();
```

or:

```bash
sudo systemctl reload postgresql
```

Check the server log for syntax errors. A bad `pg_hba.conf` line causes a reload to fail with `invalid line ... in pg_hba.conf` and the old rules stay in effect.

## 8. Protect the bind password

```bash
sudo chown postgres:postgres "$(sudo -u postgres psql -tAc 'SHOW hba_file')"
sudo chmod 600 "$(sudo -u postgres psql -tAc 'SHOW hba_file')"
```

Also:

- Use a long random password for `svc-pg-ldap`, and rotate it on a schedule. Update `pg_hba.conf` and reload when you do.
- Do not commit `pg_hba.conf` with a real password to this repository. Keep the password out of any file that is checked in.

## 9. Test PostgreSQL login

From the PostgreSQL host:

```bash
psql "host=10.0.0.20 port=5432 dbname=postgres user=alice sslmode=require"
```

Enter alice's AD password when prompted. Then:

```sql
SELECT current_user, inet_server_addr(), ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected: `current_user = alice`, `ssl = t`.

Negative tests (each must fail):

```bash
# Wrong password
psql "host=10.0.0.20 dbname=postgres user=alice sslmode=require"   # type a wrong password

# User not in pg_users (Option A) -> "LDAP authentication failed for user alice"
psql "host=10.0.0.20 dbname=postgres user=bob sslmode=require"

# Plain host without SSL -> no matching pg_hba.conf entry
psql "host=10.0.0.20 dbname=postgres user=alice sslmode=disable"
```

## 10. Troubleshooting

| Symptom in PostgreSQL log | Likely cause | Fix |
|---|---|---|
| `could not perform initial LDAP bind for ldapbinddn ... Invalid credentials` | Wrong `ldapbinddn` or password for `svc-pg-ldap` | Re-test with `ldapsearch` (section 6) |
| `LDAP authentication failed for user "alice"` | User not found, or not in `pg_users` | Check `(sAMAccountName=alice)` search with `ldapsearch` |
| `certificate verify failed` | Linux does not trust the AD CA | Redo section 4 CA steps; check `TLS_CACERT` |
| `certificate subject ... does not match` | Client connected by IP, or DC cert has no FQDN SAN | Use `dc01.corp.local` everywhere |
| `could not connect to LDAP server ... Can't contact LDAP server` | Firewall, DNS, or wrong port | Section 2 and section 1 checks |
| `password authentication failed for user "alice"` with correct password | AD account locked, disabled, or password expired | `Get-ADUser alice -Properties LockedOut,Enabled,PasswordExpired` |
| `FATAL: no pg_hba.conf entry for host ...` | Client IP not in the `ADDRESS` column, or connection not SSL and rule is `hostssl` | Fix the address or use `sslmode=require` |
| `role "alice" does not exist` | Missing PostgreSQL role | Section 7b |
| Rules changed but no effect | Reload not run, or an earlier rule matches first | `SELECT * FROM pg_hba_file_rules;` then reload |

Check the DC side when in doubt. Event ID 4625 (failed logon) and 4771 (Kerberos pre-auth failed) in the Security log of `dc01` show why AD rejected a bind.

## 11. Optional: Linux host login against AD (sssd)

Use this only if you also want OS logins on the PostgreSQL host to use AD accounts. It is separate from PostgreSQL authentication.

```bash
sudo apt install -y sssd sssd-tools realmd adcli
sudo realm join --user=Administrator corp.local
realm list
id alice@corp.local
```

Use `realm permit -g pg_users@corp.local` (or `realm permit alice@corp.local`) to restrict logins to the same group.

## 12. Checklist

- [ ] `Get-ADDomain` and `dcdiag /q` clean on `dc01`
- [ ] DNS SRV record for `_ldap._tcp.corp.local` resolves from the PostgreSQL host
- [ ] Ports 389 and 636 open between hosts
- [ ] `svc-pg-ldap` created, read-only, not a domain admin
- [ ] `pg_users` group created and test user added
- [ ] AD CS installed, DC certificate present, CA exported and trusted on Linux
- [ ] `openssl s_client` to `dc01.corp.local:636` returns `Verify return code: 0 (ok)`
- [ ] `ldapsearch` and `ldapwhoami` succeed from the PostgreSQL host
- [ ] `pg_hba.conf` uses `hostssl` with the LDAP options; file owned by `postgres`, mode `600`
- [ ] PostgreSQL roles created for each AD user
- [ ] Positive and negative login tests pass
