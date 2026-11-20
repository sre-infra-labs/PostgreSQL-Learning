## 1. Enable TCP connections for remote devices

Edit `postgresql.conf` (or better, a file in `conf.d/`):

```conf
listen_addresses = '*'          # or a specific IP, e.g. '127.0.0.1,192.168.0.10'
port = 5432
password_encryption = scram-sha-256
```

Add client access rules to `pg_hba.conf`. Rules are evaluated top to bottom, first match wins, so put specific rules above general ones:

```conf
# TYPE  DATABASE  USER      ADDRESS            METHOD
# Local (Unix socket): peer authentication for every OS user
local   all       all                          peer
# Localhost: password (scram-sha-256)
host    all       all       127.0.0.1/32       scram-sha-256
host    all       all       ::1/128            scram-sha-256
# LAN only: password (scram-sha-256) for all users in 192.168.0.0/16
host    all       all       192.168.0.0/16     scram-sha-256
# Allow remote replication connections
host    replication     all             192.168.0.0/16     scram-sha-256
```

Policy: no rule may use `0.0.0.0/0` or any other public range. Do not add a `local` line for a single user above the `local all all peer` line, because the first match wins and would change that user's method.

Verify the active rules and check that nothing is open to the internet:

```sql
SELECT line_number, type, database, user_name, address, netmask, auth_method, error
FROM pg_hba_file_rules
ORDER BY line_number;
```

Open the port on the host firewall (Ubuntu example):

```bash
sudo ufw allow from 192.168.0.0/16 to any port 5432 proto tcp
sudo ufw status
```

Apply changes:

```bash
sudo systemctl restart postgresql            # required after listen_addresses / shared_preload_libraries changes
# or, for pg_hba.conf only:
sudo -u postgres psql -c 'SELECT pg_reload_conf();'
```

Test from a remote device:

```bash
psql -h <server-ip> -p 5432 -U postgres -d postgres
```

Troubleshooting: `FATAL: no pg_hba.conf entry for host ...` means no `pg_hba.conf` line matches the client IP / user / database. Fix the rule, then reload.

Reference: https://dba.stackexchange.com/a/84002
