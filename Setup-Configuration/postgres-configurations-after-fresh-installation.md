# Instructions for configurations required after fresh postgres installation

Replace `<ver>` with your major version (for example `16`) and `<cluster>` with the cluster name (usually `main` on Ubuntu/Debian).

Ubuntu/Debian paths used below:
- Config directory: `/etc/postgresql/<ver>/<cluster>/`
- `postgresql.conf`: `/etc/postgresql/<ver>/<cluster>/postgresql.conf`
- `pg_hba.conf`: `/etc/postgresql/<ver>/<cluster>/pg_hba.conf`
- Drop-in config directory: `/etc/postgresql/<ver>/<cluster>/conf.d/` (used for custom settings, e.g. `dba.conf`)
- Data directory: `/var/lib/postgresql/<ver>/<cluster>`

RHEL/Fedora paths are usually `/var/lib/pgsql/<ver>/data/` for data and config.

---

## 0. Verify the server is up and find the config files

```bash
sudo systemctl status postgresql
sudo -u postgres psql -c 'SELECT version();'
sudo -u postgres psql -c 'SHOW config_file;'
sudo -u postgres psql -c 'SHOW hba_file;'
sudo -u postgres psql -c 'SHOW data_directory;'
```

Set a password for the `postgres` superuser (needed for TCP/password logins):

```sql
ALTER USER postgres PASSWORD 'newpassword';
```

Forgot the password? Connect through the local Unix socket as the OS `postgres` user (`sudo -u postgres psql`) and run the same `ALTER USER`. Source: https://askubuntu.com/a/594002

---

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
local   all       all                          peer
host    all       all       127.0.0.1/32       scram-sha-256
host    all       all       ::1/128            scram-sha-256

# Replace with your LAN / client subnet
host    all       postgres  192.168.0.0/16     scram-sha-256
host    all       all       192.168.0.0/16     scram-sha-256
```

Some other examples used in this learning repo:

```conf
# "local" is for Unix domain socket connections only
local   all   ajay     scram-sha-256
local   all   saanvi   peer
local   all   all      peer

# IPv4
host    all   saanvi   0.0.0.0/0      scram-sha-256
host    all   ajay     0.0.0.0/0      scram-sha-256
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

---

## 2. Memory and resource settings

Put these in `conf.d/dba.conf` (or `postgresql.conf`). Starting points for a dedicated DB server; adjust to RAM:

```conf
shared_buffers = 4GB             # ~25% of RAM is a common starting point (requires restart)
work_mem = 64MB                  # per sort/hash operation, per connection; keep modest
maintenance_work_mem = 2GB       # VACUUM, CREATE INDEX, ALTER TABLE ADD FK
wal_buffers = -1                 # auto (1/32 of shared_buffers, max 16MB)
effective_cache_size = 12GB      # planner hint: RAM available for OS cache + shared_buffers
max_connections = 200            # keep low; use a pooler (pgbouncer) for many clients
```

Notes:
- `shared_buffers` and `max_connections` need a restart. `work_mem`, `maintenance_work_mem`, `effective_cache_size` only need a reload.
- `work_mem` is multiplied by concurrent sorts/hashes, so do not set it high globally. Raise it per session when needed: `SET work_mem = '256MB';`

Apply and verify:

```bash
sudo systemctl restart postgresql
```

```sql
SELECT name, setting, unit, source, sourcefile
FROM pg_settings
WHERE name IN ('shared_buffers','wal_buffers','work_mem','maintenance_work_mem','effective_cache_size','max_connections');
```

---

## 3. Logging

Logs go to `/var/log/postgresql/`, rotated by size (100 MB) and age (every 1 hour). This matches the logrotate/pgBadger setup below.

```bash
sudo mkdir -p /var/log/postgresql
sudo chown postgres:postgres /var/log/postgresql
sudo chmod 0750 /var/log/postgresql
```

`conf.d/dba.conf`:

```conf
logging_collector = on
log_destination = 'stderr'
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = '1h'
log_rotation_size = '100MB'
log_truncate_on_rotation = off

log_line_prefix = '%m [%p] %q%u@%d '
log_min_messages = 'warning'
log_min_error_statement = 'error'
log_lock_waits = on
deadlock_timeout = '5s'
log_temp_files = '20MB'
log_checkpoints = on
log_connections = on
log_disconnections = on
```

For pgBadger-compatible logs (optional, see `pgBadger-settings.md`):

```conf
log_min_duration_statement = 500
log_statement_sample_rate = 0.8
log_transaction_sample_rate = 0.5
```

Apply:

```bash
sudo systemctl restart postgresql
```

Verify:

```sql
SHOW logging_collector;
SHOW log_directory;
SHOW log_filename;
SHOW log_rotation_age;
SHOW log_rotation_size;
```

Logrotate config is in `etc_logrotate.d_postgresql` (rotate at 500 MB, keep 5) and the cron schedule is in `etc_cron.d_logrotate_postgresql.conf` (every 15 minutes). Install:

```bash
sudo cp /stale-storage/GitHub/PostgreSQL-Learning/Setup-Configuration/etc_logrotate.d_postgresql /etc/logrotate.d/postgresql
sudo cp /stale-storage/GitHub/PostgreSQL-Learning/Setup-Configuration/etc_cron.d_logrotate_postgresql.conf /etc/cron.d/logrotate_postgresql
sudo chown root:root /etc/cron.d/logrotate_postgresql
sudo chmod 0644 /etc/cron.d/logrotate_postgresql
sudo logrotate -d /etc/logrotate.d/postgresql     # dry run
```

Reference: `book--learn-postgres/chp14-logging-and-auditing.md`

---

## 4. Find out the active config value source file

```sql
-- check setting details
SELECT name, setting, unit, source, sourcefile, sourceline
FROM pg_settings
WHERE name = 'shared_preload_libraries';

-- check setting source
SELECT sourcefile, sourceline, seqno, name, setting, applied
FROM pg_file_settings
WHERE name = 'shared_preload_libraries';

-- find every setting that is NOT at its default value
SELECT name, setting, unit, source, sourcefile, sourceline
FROM pg_settings
WHERE source NOT IN ('default', 'override')
ORDER BY sourcefile, name;

-- find settings set at database or role level
SELECT d.datname AS database, r.rolname AS role, s.setconfig
FROM pg_db_role_setting s
LEFT JOIN pg_database d ON d.oid = s.setdatabase
LEFT JOIN pg_roles r ON r.oid = s.setrole;

-- get some common settings
SHOW config_file;
SHOW hba_file;
SHOW data_directory;
SHOW log_destination;
SHOW log_directory;
SHOW log_filename;
SHOW shared_preload_libraries;
```

Check whether a change needs a restart or only a reload:

```sql
SELECT name, context FROM pg_settings WHERE name IN ('shared_buffers','work_mem','listen_addresses','shared_preload_libraries');
-- context = postmaster -> restart; sighup -> pg_reload_conf(); user/superuser -> session level
```

Reload after editing files:

```sql
SELECT pg_reload_conf();
```

Settings made with `ALTER SYSTEM` go to `postgresql.auto.conf`. Remove one with `ALTER SYSTEM RESET <name>;` or all with `ALTER SYSTEM RESET ALL;`.

---

## 5. Extensions

### 5.1 Install the packages (Ubuntu/Debian, PGDG repo)

Add the PostgreSQL apt repo first (see https://www.postgresql.org/download/linux/ubuntu/), then:

```bash
sudo apt update
sudo apt install -y postgresql-<ver>-pgaudit
sudo apt install -y postgresql-<ver>-cron            # pg_cron
sudo apt install -y postgresql-<ver>-repack          # pg_repack
sudo apt install -y postgresql-<ver>-partman         # pg_partman
sudo apt install -y postgresql-<ver>-pglogical
sudo apt install -y postgresql-<ver>-wal2json
sudo apt install -y postgresql-<ver>-pg-hint-plan
sudo apt install -y postgresql-<ver>-pg-wait-sampling
sudo apt install -y postgresql-contrib               # pg_stat_statements, auto_explain, pg_trgm, pg_buffercache, postgres_fdw ...
```

Not sure of a package name? Search for it:

```bash
apt search postgresql-<ver> | grep -i <extension-name>
```

Extensions that are not packaged (for example `pg_stat_plans`, `pg_plan_advice` on pg19+) must be built from source with `make USE_PGXS=1 install PG_CONFIG=/usr/lib/postgresql/<ver>/bin/pg_config`. Example from `book--learn-postgres/chp19-useful-tools-n-extensions.md` (pg_stat_monitor).

### 5.2 Extensions that must be preloaded (`shared_preload_libraries`)

Extensions in this list need a server restart after being added. Set them in one place (`conf.d/dba.conf`), not in several:

```conf
shared_preload_libraries = 'pg_stat_statements,auto_explain,pgaudit,pg_cron,pg_wait_sampling'

# pg_cron needs a database to hold its job table
cron.database_name = 'postgres'
```

Or use `ALTER SYSTEM` (writes to `postgresql.auto.conf`):

```sql
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements,auto_explain,pgaudit,pg_cron';
```

Then restart:

```bash
sudo systemctl restart postgresql
```

Confirm:

```sql
SHOW shared_preload_libraries;
```

Note: when you set `shared_preload_libraries` with `ALTER SYSTEM`, it replaces the whole list. Include every library you need.

### 5.3 auto_explain (log plans of slow queries)

```conf
session_preload_libraries = 'auto_explain'     # no restart needed; reload
auto_explain.log_min_duration = '1000ms'
auto_explain.log_analyze = on
auto_explain.log_buffers = on
auto_explain.log_timing = on
auto_explain.log_format = 'json'
auto_explain.log_nested_statements = on
```

Per-database override:

```sql
ALTER DATABASE postgres_air SET auto_explain.log_min_duration = '1000ms';
```

### 5.4 pg_stat_statements (find the most expensive queries)

Requires `shared_preload_libraries` (see 5.2), then in each database you want to track:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Reference: `book--learn-postgres/chp19-useful-tools-n-extensions.md`

### 5.5 pgaudit (audit logging)

Requires `shared_preload_libraries = '...pgaudit...'`, then:

```sql
CREATE EXTENSION IF NOT EXISTS pgaudit;

-- Audit writes and DDL
ALTER SYSTEM SET pgaudit.log = 'write, ddl';
SELECT pg_reload_conf();
```

Other values for `pgaudit.log`: `ALL, NONE, READ, WRITE, ROLE, DDL, FUNCTION, MISC, MISC_SET`. Role-based auditing: create a role, grant it the tables to audit, then `ALTER SYSTEM SET pgaudit.role = 'pgaudit_role';`. Reference: `book--learn-postgres/chp14-logging-and-auditing.md`

### 5.6 Other extensions (create in the database where needed)

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;          -- trigram indexes for LIKE / ILIKE / fuzzy search
CREATE EXTENSION IF NOT EXISTS pg_buffercache;   -- inspect shared_buffers contents
CREATE EXTENSION IF NOT EXISTS postgres_fdw;     -- query other PostgreSQL servers
CREATE EXTENSION IF NOT EXISTS pg_partman;       -- automated partition management
CREATE EXTENSION IF NOT EXISTS pg_repack;        -- online table/index bloat removal
CREATE EXTENSION IF NOT EXISTS pglogical;        -- logical replication (needs wal_level = logical)
CREATE EXTENSION IF NOT EXISTS wal2json;         -- logical decoding output plugin (no CREATE needed; used by slots)
CREATE EXTENSION IF NOT EXISTS pg_hint_plan;     -- plan hints in /*+ ... */ comments
```

`pg_hint_plan` only works when preloaded: add it to `shared_preload_libraries`.
`pglogical` and `wal2json` for logical replication need `wal_level = logical` (restart required).

### 5.7 Verify installed extensions

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
ORDER BY name;
```

---

## 6. Set up database maintenance jobs using pg_cron

Requires `pg_cron` in `shared_preload_libraries` and `cron.database_name` (see 5.2).

```sql
-- run in the database set by cron.database_name (default 'postgres')
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Example jobs (times are server time, cron syntax)
SELECT cron.schedule('nightly-analyze', '30 2 * * *', 'ANALYZE');
SELECT cron.schedule('weekly-vacuum-analyze', '0 3 * * 0', 'VACUUM (ANALYZE)');

-- review jobs and their run history
SELECT jobid, jobname, schedule, command, database, active FROM cron.job;
SELECT jobid, status, return_message, start_time, end_time FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;

-- remove a job
SELECT cron.unschedule('nightly-analyze');
```

Use `cron.schedule_in_database(job_name, schedule, command, database)` to run a job in a database other than `cron.database_name`.

---

## 7. Enable vacuuming (autovacuum)

Autovacuum is on by default. Confirm it, then tune the important parameters:

```sql
SHOW autovacuum;

SELECT name, setting FROM pg_settings
WHERE name IN ('autovacuum','autovacuum_max_workers','autovacuum_naptime',
               'autovacuum_vacuum_scale_factor','autovacuum_analyze_scale_factor',
               'autovacuum_vacuum_cost_limit');
```

Starting point in `conf.d/dba.conf`:

```conf
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = '30s'
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_scale_factor = 0.02
autovacuum_vacuum_cost_limit = 2000
```

Find tables that need attention:

```sql
SELECT relname, n_dead_tup, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;
```

---

## 8. Enable stats collection

Statistics collection is on by default (`track_counts`, `track_activities`, `track_io_timing` is off by default).

```conf
track_counts = on
track_activities = on
track_activity_query_size = 4096
track_io_timing = on             # small overhead; useful for EXPLAIN (BUFFERS) and pg_stat_statements
```

Verify:

```sql
SHOW track_counts;
SHOW track_io_timing;
```

Reset counters when needed:

```sql
SELECT pg_stat_reset();                      -- database-level counters
SELECT pg_stat_statements_reset();           -- after pg_stat_statements is installed
```

---

## 9. Backups with pgBackRest

For backup, we use `/vm-storage-02/pgbackrest/<pg-server-hostname>` as the repo path. This is a Samba shared directory.

### 9.1 Install

```bash
sudo apt update && sudo apt install -y pgbackrest      # Ubuntu/Debian
sudo dnf install -y pgbackrest                         # RHEL/Fedora
```

### 9.2 Create the repo directory on the Samba share

```bash
sudo mkdir -p /vm-storage-02/pgbackrest/$(hostname)
sudo chown -R postgres:postgres /vm-storage-02/pgbackrest/$(hostname)
sudo chmod 0750 /vm-storage-02/pgbackrest/$(hostname)
```

Samba mount notes are in `book--learn-postgres/chp19-useful-tools-n-extensions.md` (section "Samba Shared Directory for pgbackrest of remote PostgreSQL Servers").

### 9.3 Create `/etc/pgbackrest/pgbackrest.conf`

```ini
[global]
repo1-path=/vm-storage-02/pgbackrest/<pg-server-hostname>
repo1-retention-full=2
repo1-retention-diff=6
start-fast=y
log-level-console=info
log-level-file=detail
log-path=/var/log/pgbackrest
process-max=2

[main]
pg1-path=/var/lib/postgresql/<ver>/<cluster>
pg1-port=5432
pg1-user=postgres
```

```bash
sudo mkdir -p /var/log/pgbackrest
sudo chown postgres:postgres /var/log/pgbackrest
sudo mkdir -p /etc/pgbackrest
sudo nano /etc/pgbackrest/pgbackrest.conf
sudo chown postgres:postgres /etc/pgbackrest/pgbackrest.conf
sudo chmod 0640 /etc/pgbackrest/pgbackrest.conf
```

### 9.4 Enable WAL archiving in `conf.d/dba.conf`

```conf
wal_level = replica
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
archive_timeout = 60
```

Restart PostgreSQL (`archive_mode` needs a restart):

```bash
sudo systemctl restart postgresql
```

### 9.5 Create the stanza, check, and take the first backup

```bash
sudo -u postgres pgbackrest --stanza=main stanza-create
sudo -u postgres pgbackrest --stanza=main check
sudo -u postgres pgbackrest --stanza=main backup --type=full
sudo -u postgres pgbackrest info
```

Schedule backups with pg_cron (section 6) or cron:

```bash
# /etc/cron.d/pgbackrest
30 0 * * 0 postgres pgbackrest --stanza=main backup --type=full
30 0 * * 1-6 postgres pgbackrest --stanza=main backup --type=diff
```

Reference: `book--learn-postgres/chp19-useful-tools-n-extensions.md` (section "Disaster Recovery with pgbackrest") and `book--learn-postgres/chp15-backup-and-restore.md`.

---

## 10. Configure pg_exporter and add to Prometheus

Not yet documented. Add steps here (install `postgres_exporter`, create a monitoring role, add the scrape job to `prometheus.yml`).

---

## 11. pgBadger setup

### 11.1 pgbadger part 01: Setup Multi-Server pgbadger environment on localhost ryzen9 (ubuntu 26) machine

See `Setup-Configuration/pgBadger-settings.md`:

```bash
sudo apt install pgbadger -y
sudo mkdir -p /var/lib/pgbadger/data/html
sudo chown -R postgres:www-data /var/lib/pgbadger/
sudo chmod 770 -R /var/lib/pgbadger/
```

### 11.2 pgbadger part 02: Add the PostgreSQL cluster to above pgbadger environment

Use the logging settings in section 3, then import the logs:

```bash
pgbadger -o /var/lib/pgbadger/data/html/first_report.html /var/log/postgresql/postgresql*
```

Incremental import from a remote host:

```bash
pgbadger -I --outdir /var/lib/pgbadger/data/html/<pg-server-hostname> ssh://postgres@<pg-server-hostname>//var/log/postgresql/postgresql*
```

The SSH user needs read access to the logs and passwordless SSH key login (see section 12).

---

## 12. Passwordless SSH between hosts (for remote log / backup access)

```bash
sudo -u postgres ssh-keygen -t ed25519 -N ''
sudo -u postgres ssh-copy-id postgres@<remote-host>     # or copy ~postgres/.ssh/id_ed25519.pub manually
sudo -u postgres ssh postgres@<remote-host> 'echo ok'
```

---

## 13. Install and configure pgwatch

Not yet documented. pgwatch2 (dockerized, dashboard, alerts) is described in `book--learn-postgres/chp19-useful-tools-n-extensions.md`. Add the install and config steps here.

---

## 14. Shell and psql conveniences

Make `sudo -u postgres` sessions show the host and time:

Add to `~postgres/.bashrc` (and make sure `~postgres/.profile` sources it):

```bash
GREEN='\[\033[32m\]'
RED='\[\033[31m\]'
YELLOW='\[\033[33m\]'
BLUE='\[\033[34m\]'
RESET='\[\033[0m\]'
NEWLINE='\n'

PS1="----- ${GREEN}[\$(date +'%Y-%b-%d %H:%M:%S')]${RESET} ${RED}\u${RESET}@${YELLOW}\h${RESET} ${BLUE}(\$(pwd | sed -e 's|.*/||'))${RESET}${NEWLINE}|------------\$ "
unset color_prompt force_color_prompt
```

```bash
# ~postgres/.profile
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi
```

Add to `~/.psqlrc` (see `Setup-Configuration/psql-prompt.sh`):

```text
\set PROMPT1 '%[%033[96m%]%n@%[%033[95m%]%m %[%033[39m%][%`date +%H:%M:%S`] %[%033[92m%](%/) \n%[%033[1;33m%]%R%#%]%[%033[0;39m%]%] '
\set PROMPT2 '%[%033[1;33m%]%R%#%]%[%033[0;39m%]%] '
```

Client tools (make `pg_dump` match the server version):

```bash
sudo apt install -y postgresql-client-<ver>
sudo ln -sfn /usr/lib/postgresql/<ver>/bin/pg_dump /usr/bin/pg_dump
```

Environment variables (`~/.bashrc`):

```bash
export EDITOR=nano
export PGDATABASE=postgres_air
export PGSERVICEFILE=~/.pg_service.conf
export PGPASSWORD='<password>'      # prefer ~/.pgpass (chmod 600) instead
```

---

## 15. Restore sample databases

Use `Setup-Configuration/restore-sample-dbs.sh` (stackoverflow2013 is restored into its own tablespace).

```sql
CREATE TABLESPACE stackoverflow2013 LOCATION '/path/to/tablespace';
```

---

## 16. Final verification checklist

```sql
SELECT version();
SHOW listen_addresses;
SHOW port;
SHOW shared_buffers;
SHOW work_mem;
SHOW maintenance_work_mem;
SHOW shared_preload_libraries;
SHOW logging_collector;
SHOW log_directory;
SHOW archive_mode;
SHOW autovacuum;
SHOW track_counts;
SELECT name FROM pg_available_extensions WHERE installed_version IS NOT NULL;
```

From a remote machine:

```bash
psql -h <server-ip> -U postgres -d postgres -c 'SELECT 1;'
```

Outstanding (to be documented): pg_exporter + Prometheus, pgwatch.
