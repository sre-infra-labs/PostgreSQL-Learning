# Check where the setting is coming from
```
show log_rotation_age;

SELECT name, setting, source, sourcefile, sourceline
FROM pg_settings
WHERE name = 'log_rotation_age';

select pg_reload_conf();
```


# Changes for PostgreSQL.conf

## `auto_explain` to Capture Execution Plans for Slow Queries

`EXPLAIN (ANALYZE, SETTINGS, COSTS, TIMING, SUMMARY, WAL, VERBOSE, BUFFERS, FORMAT JSON)`


```
session_preload_libraries = 'auto_explain'

auto_explain.log_min_duration = '1000ms'
auto_explain.log_format = 'json'
auto_explain.log_verbose = 'on'
auto_explain.log_analyze = 'on'
auto_explain.log_buffers = 'on'
auto_explain.log_wal = 'on'
auto_explain.log_timing = 'on'
auto_explain.log_triggers = 'on'
auto_explain.log_summary = 'on'
auto_explain.log_settings = 'on'
auto_explain.log_nested_statements = on

```

## `pg_stat_statements` to Capture Slow Queries

```
shared_preload_libraries = 'pg_stat_statements'    # (change requires restart)

logging_collector = on
log_destination = 'stderr'
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
#log_filename = 'postgresql-%a.log'
log_rotation_age = '1h'
log_rotation_size = '50MB'

log_min_messages = 'info'
client_min_messages = 'warning'

log_min_duration_statement = '5s'
log_min_duration_sample = '2s'
log_statement_sample_rate = 0.1
log_transaction_sample_rate = 0.1

log_temp_files = '20MB'

# Indicate locking issues
log_lock_waits = on
deadlock_timeout = '5s'

log_line_prefix = '%m [%p] %a@@%h [%l] %q%u@%d '
# default
log_line_prefix = '%m [%p] %q%u@%d '

```

# Log Analysis for pgbadger
### Check [../Setup-Configuration/pgBadger-settings.md](../Setup-Configuration/pgBadger-settings.md)

# [Install PgAudit on Ubuntu for PostgreSQL 16](https://support.kaspersky.com/kuma/2.1/252059)
```
# Add the PostgreSQL 16 repository.
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# Import the repository signing key.
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

# Update the package list
sudo apt update

# Install pgaudit
sudo apt -y install postgresql-<PostgreSQL version>-pgaudit
sudo apt -y install postgresql-16-pgaudit

# Edit postgresql.conf
shared_preload_libraries = 'pgaudit'


```

# Implementing Auditing using PgAudit
```
# create pgaudit extension for audit database
create extension pgaudit;


prepare my_query(text) as select * from users where displayname like $1;
execute my_query('Ajay%');

# Possible value for pgaudit.log -> ALL, NONE, READ, WRITE, ROLE, DDL, FUNCTION, MISC, MISC_SET
pgaudit.log = 'WRITE,FUNCTION'
set pgaudit.log to 'write, function';

# Possible value for pgaudit.log_level -> debug1-debug5, info, notice, warning, error, log, fatal, panic
pgaudit.log_level = 'INFO'

# Configure additional query parameters
pgaudit.log = 'write, ddl'

# Configure pgaudit by Object
pgaudit.role = 'pgaudit_role'

```

# Auditing by session
```
# Possible value for pgaudit.log -> ALL, NONE, READ, WRITE, ROLE, DDL, FUNCTION, MISC, MISC_SET

-- set log at session level (only superuser)
set pgaudit.log to 'write, ddl';

select count(*) from users;

-- Check how log_statement extension logs it vs how PgAudit logs the information for dynamic sql
DO $$ BEGIN
EXECUTE 'TRUNCATE TABLE ' || 'public.users_new cascade';
END $$;

```


# Auditing by Role
```
-- create a role to template permissions to audit
create role pgaudit_role with nologin;

-- grant role to specific users for auditing their queries only
grant pgaudit_role to analyst_user;

-- provide template permissions to audit
grant insert,update,select on users_new to pgaudit_role;
grant update on users to pgaudit_role;

-- start auditing based on role
set pgaudit.role to pgaudit_role;

-- In postgresql.conf
pgaudit.role = 'pgaudit_role'

```

# Reset all settings
```
-- Reset a single setting
ALTER SYSTEM RESET shared_preload_libraries;
ALTER SYSTEM RESET max_connections;

-- Or for session-level settings
RESET work_mem;
RESET statement_timeout;

-- Reset all settings for entire server;
ALTER SYSTEM RESET ALL;

-- This resets all settings in postgresql.auto.conf
SELECT pg_reload_conf();

```