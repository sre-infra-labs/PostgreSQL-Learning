# Starting the database server manually

`sudo systemctl start SERVICEUNIT`

### On Debian/Ubuntu, service unit looks like
```
postgresql@RELEASE-CLUSTERNAME.service
```

### For Debian/Ubuntu, there is another service that manages all databases instance all at once
`postgresql`

### Default RedHat packages calls the service unit
`postgresql`

### Redhat packages from PostgreSQL Yum repository
```postgresql-RELEASE

sudo systemctl start postgresql-16
```

### On Debian/Ubuntu, start/stop/status of postgresql cluster
```
# get available clusters
pg_lsclusters

    Ver Cluster Port Status Owner    Data directory              Log file
    16  main    5432 online postgres /var/lib/postgresql/16/main /var/log/postgresql/postgresql-16-main.log

# get status using systemd
sudo systemctl status postgresql@16-main.service

# get cluster status using native tool
sudo -u postgres pg_ctlcluster 16 main status

    pg_ctl: server is running (PID: 5791)
    /usr/lib/postgresql/16/bin/postgres "-D" "/var/lib/postgresql/16/main" "-c" "config_file=/etc/postgresql/16/main/postgresql.conf"

# get cluster status using service utility
sudo service postgresql@16-main status status

# Get process running state
cat /etc/postgresql/16/main/start.conf
    ----- [2025-Dec-05 04:52:53] postgres@ryzen9 (postgresql)
    |------------$ ls -l /etc/postgresql/16/main/start*
    -rw-r--r-- 1 postgres postgres 317 Apr  6  2024 /etc/postgresql/16/main/start.conf
    |------------$ cat /etc/postgresql/16/main/start.conf
    auto

```

### On RedHat, start/stop/status of postgresql cluster
```
# get status using systemd
sudo systemctl status postgresql-16.service
or
sudo systemctl status postgresql.service

# get status using service utility
sudo service postgresql@16 status

# get status using pg_ctl
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/15/data status
```

### On Windows
```
net start postgresql-x64-16
```


# Stopping postgresql safely and quickly
```
sudo systemctl stop SERVICEUNIT

pg_ctlcluster RELEASE CLUSTERNAME stop -m fast

pg_ctl -D $PGDATADIR -m fast stop
```

# Stopping postgresql in emergency
```
pg_ctlcluster RELEASE CLUSTERNAME stop -m immediate

pg_ctl -D $PGDATADIR -m immediate stop

```

# Reloading server configuration files
```
sudo systemctl reload SERVICEUNIT

pg_ctlcluster RELEASE CLUSTERNAME reload
    pg_ctlcluster 16 main reload

service postgresql-16 reload

pg_ctl -D /var/lib/pgsql/16/data reload

postgres=# SELECT pg_reload_conf();
```

# Which setting change need reload?

- `context` equal to `sighup` in `pg_settings`

```
-- Some settings worth changing
select name, setting, unit, (source = 'default') as is_default
from pg_settings
where context = 'sighup'
and (name like '%delay' or name like '%timeout')
and setting != '0';

```

# Speed up server cache?

Preloading data pages in cache after reboot can boot performance.

- `pgfincore` extension implements a set of functions to manage PostgreSQL data pages in the operation system's file cache.
- `pg_prewarm` extension, part of contrib module, helps preload shared buffer cache.


# Preventing new Connections

1. Pause & resume session pool
2. Stop the server
3. `alter database stackoverflow connection limit 0;`
   - rollback - `alter database stackoverflow connection limit -1;`
4. `alter user sqlquerystress connection limit 0;`
   - rollback - `alter user sqlquerystress connection limit -1;`
5. Update `pg_hba.conf` file
   - reject all tcp ip connections - `host all all 0.0.0.0/0 reject`

```
-- set connection limit set for users
select rolname, rolconnlimit from pg_roles;
```

# Kill users from server

```
-- How to kill user session
select pg_terminate_backend(pid)
from pg_stat_activity
where ...

where application_name = 'myapp'
where wait_event_type != 'Activity'
where state != 'idle in transaction'
where usename = 'foo'
```

### Kill non-admin connections
```
select count(pg_terminate_backend(pid))
from pg_stat_activity
where usename not in (select username from pg_user where usesuper);
```

# Fix permissions for Multitenancy

- With `usage` permission, only viewing/listing of the objects are allowed
- To `read` data from objects, `select` permission is needed

```
select current_schema;
show search_path;

-- Remove public schema from search path so that user cannot search object from public schema
alter role fiona set search_path = 'finance';
alter role sally set serach_path = 'sales';

-- grant all on their own schema
grant all on schema finance to fiona;
grant all on schema sales to sally;

or

-- create schema with an owner
create schema finance authorization fiona;
create schema sales authorization sally;

-- grant usage on cross schema
grant usage on schema sales to fiona;
grant usage on schema finance to sally;

-- grant select on cross schema for specific table
grant select on finance_table_01 to sally;
grant select on sales_table_01 to fiona;

-- grant default privileges so that new objects created are automatically picked up
alter default privileges for user fiona in schema finance
    grant select on tables to public;
```

## Giving users their own private database

- By default, every user of database has read/usage privileges on public schema
- By default, every database owner can list other databases, and their pubic schema

```
-- present database owner to access other databases by modifying connect permissions in single transaction

begin;
revoke connect on database financedb from public;
grant connect on database financedb to fiona;
commit;
```


