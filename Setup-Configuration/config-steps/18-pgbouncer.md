## 18. Configure PgBouncer (connection pooler)

PgBouncer keeps a small pool of real PostgreSQL connections and lets many clients share them. Use it instead of raising `max_connections` (see [section 2](02-memory-resources.md)). This setup listens on the server's LAN address and on localhost only, uses `scram-sha-256` (matching [section 1](01-tcp-connections.md)), and is reachable from `192.168.0.0/16` only.

Reference: https://www.pgbouncer.org/config.html

### 18.1 Install

```bash
sudo apt update && sudo apt install -y pgbouncer      # Ubuntu/Debian
sudo dnf install -y pgbouncer                         # RHEL/Fedora
dpkg -L pgbouncer | grep pgbouncer.ini                # Ubuntu/Debian: find the config location
```

Config files: `/etc/pgbouncer/pgbouncer.ini` and `/etc/pgbouncer/userlist.txt`.

### 18.2 Create the auth role and lookup function (in PostgreSQL)

PgBouncer checks client passwords against PostgreSQL instead of a copied list. Create a login role for PgBouncer, plus a function that returns one user's password hash. `SECURITY DEFINER` lets the function read `pg_shadow`, which only superusers can read directly.

```bash
sudo -u postgres createuser --login --pwprompt pgbouncer_auth
```

```sql
-- run as postgres, in the postgres database
CREATE OR REPLACE FUNCTION public.pgbouncer_get_auth(p_usename text)
RETURNS TABLE(usename name, passwd text)
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog
AS $$
  SELECT usename, passwd FROM pg_catalog.pg_shadow WHERE usename = p_usename;
$$;

REVOKE ALL ON FUNCTION public.pgbouncer_get_auth(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pgbouncer_get_auth(text) TO pgbouncer_auth;
```

### 18.3 Create `/etc/pgbouncer/userlist.txt` (only for the auth role)

PgBouncer needs the auth role's own SCRAM secret in this file so it can log in to run the lookup. Generate the line from PostgreSQL and append it:

```bash
sudo -u postgres psql -Atc "SELECT '\"' || usename || '\" \"' || passwd || '\"' FROM pg_shadow WHERE usename = 'pgbouncer_auth';" \
  | sudo tee /etc/pgbouncer/userlist.txt > /dev/null
sudo chown postgres:postgres /etc/pgbouncer/userlist.txt   # or the pgbouncer service user, see: systemctl cat pgbouncer
sudo chmod 0640 /etc/pgbouncer/userlist.txt
```

### 18.4 Edit `/etc/pgbouncer/pgbouncer.ini`

```ini
[databases]
; route every database name to the local PostgreSQL server
* = host=127.0.0.1 port=5432

[pgbouncer]
listen_addr = 127.0.0.1,<server-lan-ip>     ; localhost + LAN address only, never 0.0.0.0
listen_port = 6432
unix_socket_dir = /var/run/postgresql

auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
auth_user = pgbouncer_auth
auth_query = SELECT usename, passwd FROM public.pgbouncer_get_auth($1)

pool_mode = transaction
max_client_conn = 500
default_pool_size = 20
reserve_pool_size = 5
server_idle_timeout = 600

admin_users = postgres
stats_users = postgres

logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid
```

Notes:
- `pool_mode = transaction` is the usual choice. Session-level features (`SET` without `LOCAL`, advisory session locks, `LISTEN`) do not survive between transactions in this mode.
- Keep the total of `default_pool_size` across databases and users below PostgreSQL's `max_connections`, leaving room for superuser and maintenance sessions.
- Create the log directory if needed: `sudo mkdir -p /var/log/postgresql && sudo chown postgres:postgres /var/log/postgresql` (already done in [section 3](03-logging.md)).

### 18.5 Open the port on the firewall (LAN only)

```bash
sudo ufw allow from 192.168.0.0/16 to any port 6432 proto tcp
sudo ufw status
```

### 18.6 Start and enable

```bash
sudo systemctl enable --now pgbouncer
sudo systemctl status pgbouncer
sudo journalctl -u pgbouncer -n 50 --no-pager
```

### 18.7 Verify

Connect through PgBouncer with password authentication (not peer), using the same user you created in [section 0](00-verify-server.md):

```bash
psql -h 127.0.0.1 -p 6432 -U "$USER" -d postgres -c 'SELECT current_user, inet_server_port();'
```

`inet_server_port()` returns 5432 (the real server), confirming the traffic goes through the pool.

Admin console (PgBouncer's own virtual database `pgbouncer`):

```bash
psql -h 127.0.0.1 -p 6432 -U postgres -d pgbouncer -c 'SHOW POOLS;'
psql -h 127.0.0.1 -p 6432 -U postgres -d pgbouncer -c 'SHOW CLIENTS;'
psql -h 127.0.0.1 -p 6432 -U postgres -d pgbouncer -c 'SHOW STATS;'
```

Reload after editing `pgbouncer.ini` (no restart needed for most settings):

```bash
psql -h 127.0.0.1 -p 6432 -U postgres -d pgbouncer -c 'RELOAD;'
```

Troubleshooting:
- `no such user` or `password authentication failed`: check the `auth_query` role and function from 18.2, and that `userlist.txt` holds the current SCRAM secret for `pgbouncer_auth`.
- `connection refused` from another host: check `listen_addr` includes the LAN address and the ufw rule from 18.5.
- Prepared-statement errors in transaction mode: either disable server-side prepared statements in the client driver, or use PgBouncer 1.21+ and set `max_prepared_statements` in `pgbouncer.ini`.
