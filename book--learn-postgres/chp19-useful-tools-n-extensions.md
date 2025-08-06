# Disaster Recovery with pgbackrest
### [https://pgbackrest.org]
- [https://pgbackrest.org/user-guide.html#installation](https://pgbackrest.org/user-guide.html#installation)

## Enable password less ssh between pgbackrest host and postgresql host
```
# generate ssh keys
ssh-keygen

# copy keys
sudo cat /etc/shadow | grep postgres
sudo cat /etc/passwd | grep postgres
ssh-copy-id pgpoc

# copy keys if ssh-copy-id is not possible
scp ~/.ssh/id_ed25519.pub saanvi@pgpoc:/tmp/ryzen9_postgres_id.pub

# get postgres user home directory
sudo cat /etc/passwd | grep postgre

sudo mkdir -p /var/lib/postgresql/.ssh
sudo cat /tmp/ryzen9_postgres_id.pub | sudo tee -a /var/lib/postgresql/.ssh/authorized_keys > /dev/null
sudo chown -R postgres:postgres /var/lib/postgresql/.ssh
sudo chmod 700 /var/lib/postgresql/.ssh
sudo chmod 600 /var/lib/postgresql/.ssh/authorized_keys

```

## Installing pgbackrest
```
# update repos
sudo apt update -y
sudo apt upgrade -y

# install pgbackrest
sudo apt install -y pgbackrest
sudo dnf install -y pgbackrest
```

## Configure pgbackrest repo
- [https://pgbackrest.org/user-guide.html#azure-support](https://pgbackrest.org/user-guide.html#azure-support)
- [https://pgbackrest.org/user-guide.html#s3-support](https://pgbackrest.org/user-guide.html#s3-support)
- [https://pgbackrest.org/user-guide.html#gcs-support](https://pgbackrest.org/user-guide.html#gcs-support)

```
sudo vim /etc/pgbackrest/pgbackrest.conf

[global]
start-fast=y
archive-async=y
process-max=2
repo-path=/var/lib/pgbackrest
#repo-path=/vm-storage-02/pgbackrest
repo1-retention-full=2
repo1-retention-archive=5
repo1-retention-diff=3
log-level-console=info
log-level-file=info

#repo1-type=gcs
#repo1-path=/path_on the bucket
#repo1-gcs-bucket=bucket_name
#repo1-gcs-key=/etc/pgbackrest-key.json

#repo1-type=s3
#repo1-path=/pg-backups
#repo1-s3-bucket=demo-bucket
#repo1-s3-endpoint=s3.us-east-1.amazonaws.com
#repo1-s3-key=pgbackrest_repo1_s3_key
#repo1-s3-key-secret=pgbackrest_repo1_s3_key_secret
#repo1-s3-region=us-east-1
#repo1-s3-verify-tls=n
#repo1-s3-uri-style=path

[ryzen9]
pg1-host = ryzen9
pg1-path = /var/lib/postgresql/16/main
pg1-host-user = postgres
pg1-port = 5432

```

## The PostgreSQL Server Configuration

### The postgresql.conf file
```
sudo nano /etc/postgresql/16/main/postgresql.conf

    #PGBACKREST
    archive_mode = on
    wal_level = replica #logical if we have some logical replication
    archive_command = 'pgbackrest --stanza=ryzen9 archive-push %p'


# sudo systemctl restart postgresql@16-main.service
```

### The pgbackrest.conf file

```
[global]
backup-host:ryzen9
backup-user=postgres
backup-ssh-port=22
log-level-console=info
log-level-file=info

[ryzen9]
pg1-path = /var/lib/postgresql/16/main
pg1-port = 5432

```

## Creating and managing continous backups

### Creating the stanza

```
# create stanza
pgbackrest --stanza=ryzen9 stanza-create

# verify stanza
    |------------$ tree /var/lib/pgbackrest
    /var/lib/pgbackrest
    ├── archive
    │   └── ryzen9
    │       ├── 16-1
    │       │   └── 00000001000000A2
    │       │       └── 00000001000000A2000000C3-7c571bdc0b50f01cbfdee61b908ce1a54150dc67.gz
    │       ├── archive.info
    │       └── archive.info.copy
    └── backup
        └── ryzen9
            ├── backup.info
            └── backup.info.copy

    7 directories, 5 files

# Checking the stanza
pgbackrest --stanza=ryzen9 check

```

## pgbackrest.conf for backups on same pg server

```
[global]
start-fast=y
archive-async=y
process-max=2
repo-path=/var/lib/pgbackrest
#repo-path=/vm-storage-02/pgbackrest
repo1-retention-full=2
repo1-retention-archive=5
repo1-retention-diff=3

log-level-console=info
log-level-file=info

[ryzen9]
pg1-path = /var/lib/postgresql/16/main
pg1-host-user = postgres
pg1-port = 5432
```

## Managing base backups

```
# take full backup
pgbackrest --stanza=ryzen9 --type=full backup

# get information about repo
pgbackrest --stanza=ryzen9 info

# take incremental backup
pgbackrest --stanza=ryzen9 --type=incr backup

# take differential backup
pgbackrest --stanza=ryzen9 --type=diff backup

# get information about repo
pgbackrest --stanza=ryzen9 info
```

## Managing PITR (Restore)
```
pgbackrest --stanza=ryzen9 --delta --log-level-console=info --type=time "--target=2025-05-12 15:30:00" restore

select pg_wal_replay_resume();

\d
```

## To delete stanza (backup)
```
# https://pgbackrest.org/user-guide.html#delete-stanza

pgbackrest --stanza=ryzen9 stop
pgbackrest --stanza=ryzen9 stanza-delete --force
sudo systemctl status postgresql@16-main.service
```

# Using foreign data wrappers and the postgres_fdw extension
### [List of foreign data wrapper](https://wiki.postgresql.org/wiki/Foreign_data_wrappers)

## fetch data from ryzen9
```
ansible@pgpoc:~$ psql -h localhost -U postgres

\c forum_shell

set search_path to forum;

create extension postgres_fdw;

CREATE SERVER remote_ryzen9 FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'ryzen9', dbname 'forumdb');
\des

create role forum with login password 'LearnPostgreSQL';
\dg

create schema forum;

CREATE USER MAPPING FOR forum SERVER remote_ryzen9 OPTIONS (user 'forum', password 'LearnPostgreSQL');
\deu

create foreign table forum.f_categories (pk integer, title text, description text)
SERVER remote_ryzen9 OPTIONS (schema_name 'forum', table_name 'categories');

GRANT USAGE ON SCHEMA forum TO forum;
grant SELECT ON forum.f_categories to forum;

\q

psql -h localhost -U forum -d forum_shell

select * from f_categories;

```

# Exploring pg_trgm extension

```
\c forumdb

set enable_seqscan to 'off';

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON) select * from categories where title like 'Da%';

create index categories_title_btree on categories using btree (title varchar_pattern_ops);

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON) select * from categories where title like 'Da%';
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON) select * from categories where title like '%Da%';

create extension pg_trgm;

create index categories_title_trgm on categories using gin (title gin_trgm_ops);

\d categories
\di *categories*

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON) select * from categories where title like 'Da%';
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON) select * from categories where title like '%Da%';


# Clean up
\d categories

DROP INDEX IF EXISTS categories_title_btree;
DROP INDEX IF EXISTS categories_title_trgm;

DROP EXTENSION IF EXISTS pg_trgm;

RESET enable_seqscan;

```

# Migrating from SQLServer to PostgreSQL using pgloader
- [https://pgloader.io/](https://pgloader.io/)
- [https://www.youtube.com/watch?v=YKJub0zVztE](https://www.youtube.com/watch?v=YKJub0zVztE)
- [https://www.youtube.com/watch?v=oQgCNJv9Prw](https://www.youtube.com/watch?v=oQgCNJv9Prw)
- [https://github.com/dalibo/sqlserver2pgsql](https://github.com/dalibo/sqlserver2pgsql)

```
# Command to execute
pgloader source_con_string destination_con_string

# A typical connection string
db://user:pass@host:port/dbname

db -> mssql, mysql, pgsql

# Example 01

pgloader \
mssql://SQLQueryStress:SQLQueryStressPassword@sqlmonitor:1433/StackOverflow2013 \
pgsql://postgres@localhost/stackoverflow2013
```

# Migrating from SQLServer to PostgreSQL using sqlserver2pgsql
```
1. Convert schema manually or using tools like sqlserver2pgsql.
2. Export data from SQL Server using bcp:

bcp dbname.dbo.table out table.csv -c -t',' -S sqlserver -U user -P password

3. Import into PostgreSQL using COPY:

COPY tablename FROM '/path/to/table.csv' WITH CSV;
```



