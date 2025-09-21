## How to make connection to postgresql

```
# connection string method
psql "host=myhost dbname=mydb user=myuser password=mystrongpassword port=5432"

# uri format (Uniform Resource Identifier)
psql postgresql://myuser:mystrongpassword@myhost:5432/mydb

```

## How to connect when I don't know password
```
# find user used for postgresql service. Usually its postgres
ps aux | grep postgresql.conf

    [root@pg-cls2-prod1 ansible]# ps aux | grep postgresql.conf
    postgres   50418  0.0  1.2 2150876 98688 ?       S    Sep11   0:33 /usr/pgsql-16/bin/postgres -D /var/lib/pgsql/16/data --config-file=/var/lib/pgsql/16/data/postgresql.conf --listen_addresses=pg-cls2-prod1,127.0.0.1 --port=5432 --cluster_name=pg-cls2-prod --wal_level=replica --hot_standby=on --max_connections=200 --max_wal_senders=10 --max_prepared_transactions=0 --max_locks_per_transaction=512 --track_commit_timestamp=off --max_replication_slots=10 --max_worker_processes=4 --wal_log_hints=on

# connect to postgresql server using the service account user
sudo -u postgres psql

```

## Get current connection metadata
```
-- get current database
select current_database();

-- get current user
select current_user;

-- get user connect server and port. Would be null for Unix socket connections
select inet_server_addr(), inet_server_port();

-- get postgresql version
select version();

-- get connection info
\conninfo

```

## Execute non-interactive query
```
psql -c "select current_time"
```

## Execute non-interactive query from a *.sql file
```
psql -f /tmp/whatisrunning.sql

        root@ryzen9:/home/saanvi/Downloads# cat <EOF  >> /tmp/whatisrunning.sql
        bash: EOF: No such file or directory
        root@ryzen9:/home/saanvi/Downloads# cat <<EOF  >> /tmp/whatisrunning.sql
        > select current_time;
        > select /conninfo
        > select * from pg_stat_activity where state = 'active';
        > EOF
        root@ryzen9:/home/saanvi/Downloads# chown postgres:postgres /tmp/whatisrunning.sql 
        root@ryzen9:/home/saanvi/Downloads# 
        root@ryzen9:/home/saanvi/Downloads# sudo -u postgres psql -f /tmp/whatisrunning.sql 
        DEBUG:  loaded library "auto_explain"
            current_time      
        -----------------------
        05:37:05.882245+05:30
        (1 row)

        psql:/tmp/whatisrunning.sql:3: ERROR:  syntax error at or near "/"
        LINE 1: select /conninfo
```

# Some common keywords

- *command tag*: When a command is executed successfully, PostgrSQL outputs a `command tag` equal to the name of that command.
- *psql meta-command*: A meta-command is a command for the psql client, which may (or may not) send SQL to the database server.
  - \q
  - \conninfo

# Get help on psql
```
-- Get all meta commands
\?

-- Get help on DELETE sql command
\h DELETE

```

# Some useful features of psql

- Informational metacommands, such as `\d`, `\dn`, and more
- Formatting, for output, such as `\x`
- Execution timing using the `\timing` command
- Input/output and editing commands, such as `\copy`, `\i`, and `\o`
- Automatic startup files, such as `.psqlrc`
- Substitutable parameters (variables), such as `\set` and `\unset`
- Access to the OS command line using `\!`
- Crosstab views with `\crosstabview`
- Conditional execution, such as `\if`, `\elif`, `\else`, and `\endif`

# Change your password securely
  ## Unsecure method
```
-- WARNING: The below statement can also change password, but is sent to server in plain text. Hence gets record in plain text everywhere like psql history, postgresql logs, audit logs etc
alter user myuser password 'secret';
```
  ## Secure method
```
set password_encryption = 'scram-sha-256';
\password
or
alter user myuser password 'secret';

    -- This is generate a alter user statement that is sent to server
    ALTER USER postgres PASSWORD 'SCRAM-SHA-256$4096:H45+UIZiJUcEXrB9SHlv5Q==$I0mc87UotsrnezRKv9Ijqn/zjWMGPVdy1zHPARAGfVs=:nSjwT9LGDmAsMo+GqbmC2X/9LMgowTQBjUQsl45gZzA=';

# validate in postgresql logs
awk '$0 >= "2025-09-19 18:50" && $0 <= "2025-09-19 19:15"' /var/lib/postgresql/16/main/log/postgresql-Sat.log | less
alter role sre_vault_user password 'secret';

    2025-09-13 19:08:42.525 IST [1023522] psql@@[local] [1] saanvi@postgres LOG:  duration: 4.104 ms  statement: alter role sre_vault_user password 'secret';

set password_encryption = 'scram-sha-256';
alter role sre_vault_user password 'scram-sha-256';
```

# Basic connectivity test
```
pg_isready -h pg-cls2-dr1
```

# Enabling access for network/remote users
```
# modify in postgresql.conf
listen_addresses = '*'

# add entry in pg_hba.conf
    # type  database    user    cidr-address    auth-method
    host    all         all     192.168.0.0/18  scram-sha-256

# restart services
systemctl restart postgresql.conf
```

# log connection requests
```
log_connections = on
log_disconnections = on

```

# PostgreSQL wit Kubernetes
- **CloudNativePG (CNPG)** is the newest and fastest-rising kubernetes *operator* for PostgreSQL.

# [PostgreSQL with TPA](https://www.enterprisedb.com/docs/tpa/latest/)
- **Trusted Postgres Architect (TPA)** is a software based on Ansible that can be used to deploy database clusters on a variety of platforms
- 