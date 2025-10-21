# [PostgreSQL builtin & contrib Extensions](https://www.postgresql.org/docs/current/contrib.html)
- https://wiki.postgresql.org/wiki/Monitoring#check_pgactivity
- https://www.postgresql.org/docs/current/contrib.html

```


[pg_oidc_validator](https://github.com/Percona-Lab/pg_oidc_validator/tree/main)
pg_oidc_validator is an OAuth validator module for Postgres 18, providing authentication via validating Open ID Connect (OIDC) tokens.

[credcheck](https://github.com/HexaCluster/credcheck)
The credcheck PostgreSQL extension provides few general credential checks, which will be evaluated during the user creation, during the password change and user renaming

pg_stat_statements
pg_stat_statements tracks all queries that are executed on the server and records average runtime per query "class" among other parameters.

pg_stat_plans
pg_stat_plans extends on pg_stat_statements and records query plans for all executed quries. This is very helpful when you're experiencing performance regressions due to inefficient query plans due to changed parameters or table sizes.

pg_activity
pg_activity is a htop like application for PostgreSQL server activity monitoring, written in Python.

[pgmetrics](https://pgmetrics.io/)
pgmetrics collects a lot of information and statistics from a running PostgreSQL server and displays it in easy-to-read text format or export it as JSON for scripting.

pgexporter
pgexporter is Prometheus exporter for PostgreSQL server metrics.

prometheus/postgres_exporter
prometheus/postgres_exporter is Prometheus exporter for PostgreSQL server metrics.

pgwatch2
pgwatch2 is a self-contained, easy to install and highly configurable PostgreSQL monitoring tool. It is dockerized, features a dashboard and can send alerts. No extensions or superuser privileges required!

pg_fact_loader_14-2.0.1-1PGDG.f42.noarch.rpm
This extension is used for efficiently loading fact data into PostgreSQL, often used in data warehousing or ETL processes. It helps in handling large bulk inserts while maintaining the integrity of the data.
Ajay => No

[pg_ivm](https://github.com/sraoss/pg_ivm)
Incremental View Maintenance (IVM) is a way to make materialized views up-to-date in which only incremental changes are computed and applied on views rather than recomputing the contents from scratch as REFRESH MATERIALIZED VIEW does. IVM can update materialized views more efficiently than recomputation when only small parts of the view are changed.
Ajay => No

pg_partman_14-4.5.1-2.rhel8.x86_64.rpm
pg_partman is a well-known PostgreSQL extension that manages table partitioning. It automates partition creation and maintenance, which is helpful for scaling PostgreSQL for large datasets while keeping query performance high.
Ajay => Explore

pg_permissions_14-1.3-2PGDG.rhel8.noarch.rpm
This package helps manage and audit permissions in PostgreSQL. It allows database administrators to see and control object-level access permissions across schemas and tables
Ajay => Yes

pg_prioritize_14-1.0.4-2.rhel8.x86_64.rpm
This extension provides a way to prioritize certain queries or workloads in PostgreSQL. It can be used to optimize query performance for critical applications by adjusting the priority of specific queries or transactions.
Ajay => No

pg_profile_14-4.4-1PGDG.rhel8.noarch.rpm
pg_profile allows you to analyze query performance in detail, offering insights into how queries interact with the database and where bottlenecks may occur. It's useful for diagnosing performance issues.
Ajay => Explore

[pg_qualstats](https://github.com/powa-team/pg_qualstats)
A PostgreSQL extension for collecting statistics about predicates, helping find what indices are missing.
pg_qualstats is an extension that provides detailed statistics about the queries executed on a PostgreSQL database, specifically focusing on the conditions (WHERE clauses) in SQL queries. It helps DBAs and developers optimize queries by giving visibility into commonly used conditions.
Ajay => Explore

pg_repack_14-1.4.7-1.rhel8.x86_64.rpm
pg_repack is a tool used to reorganize tables and indexes in PostgreSQL databases. It helps to reclaim storage and optimize performance by removing bloat, which happens over time when data is inserted, updated, or deleted. The repacking process does this without requiring downtime, making it an excellent choice for performance tuning in high-availability environments.
Ajay => Explore

pg_show_plans_14-llvmjit-2.1.2-1PGDG.rhel8.x86_64.rpm
pg_show_plans provides detailed visibility into query plans used by PostgreSQL's query planner. By using this extension, developers and DBAs can gain insights into how queries are executed and identify potential inefficiencies. 
Ajay => Explore

pg_stat_monitor_14-0.9.2-beta1_1.rhel8.x86_64.rpm
pg_stat_monitor is an advanced monitoring extension for PostgreSQL. It collects detailed statistics about query execution, helping DBAs understand query performance, track slow queries, and identify system bottlenecks. It provides enhanced insights into system health and query execution patterns.
Ajay => Explore

pg_statement_rollback_14-1.3-1.rhel8.x86_64.rpm
pg_statement_rollback is a useful extension for monitoring SQL statements that were rolled back, offering insights into which transactions failed and why. This helps in troubleshooting issues, auditing, and tracking errors that occur in the database.
Ajay => Explore

pg_statviz_extension_14-0.4-1PGDG.rhel8.noarch.rpm
pg_statviz is a visualization tool for PostgreSQL statistics. It generates graphical representations of database performance and activity, helping DBAs visualize query performance and database load in a more intuitive way.
Ajay => Explore

pgaudit16_14-1.6.2-1.rhel8.x86_64.rpm
pgaudit is an auditing extension for PostgreSQL, which logs detailed information about SQL statements executed in the database. This is particularly useful for security, compliance, and troubleshooting purposes, as it helps track changes and access to sensitive data.
Ajay => Explore

pgauditlogtofile_14-1.3-1.rhel8.x86_64.rpm
pgauditlogtofile extends the pgaudit functionality by logging audit records to a file. This makes it easier to manage and review audit logs, especially in environments with stringent compliance requirements.
Ajay => No

pgcopydb_14-0.9-1.rhel8.x86_64.rpm
pgcopydb is a tool designed for PostgreSQL that provides an efficient and fast way to copy large amounts of data between PostgreSQL databases. It uses parallel processing to speed up the data transfer process, making it suitable for backup and migration scenarios, especially for large databases.
Ajay => No

pgexporter_ext_14-0.1.0-1.rhel8.x86_64.rpm
pgexporter_ext is an extension used in conjunction with Prometheus's postgres_exporter to collect and export PostgreSQL metrics
Ajay => Yes

pgmemcache_14-2.3.0-5.rhel8.x86_64.rpm
pgmemcache integrates PostgreSQL with Memcached, a popular caching system. This extension allows PostgreSQL to store and retrieve data from Memcached, enhancing query performance by reducing the need for frequent database lookups.
Ajay => Explore

pgmeminfo_14-1.0.0-1PGDG.rhel8.x86_64.rpm
pgmeminfo provides memory-related statistics for PostgreSQL, giving insights into how memory is being used by the database. This can be particularly useful for troubleshooting memory issues and optimizing memory usage
Ajay => Explore

pgtap_14-1.3.3-1PGDG.rhel8.noarch.rpm
pgtap is a unit testing framework for PostgreSQL. It allows developers to write tests for their PostgreSQL functions and queries, which helps ensure the reliability and correctness of database operations.
Ajay => No

pgtt_14-2.10-1.rhel8.x86_64.rpm
pgtt is a PostgreSQL extension for managing time travel tables. It allows users to store and query historic
Ajay => No

powa-archivist_14-4.2.0-1PGDG.rhel7.x86_64.rpm
this is part of the POWA (PostgreSQL Workload Analyzer) suite, which helps monitor PostgreSQL performance over time. The archivist collects historical statistics for analysis and troubleshooting
Ajay => Explore

plpgsql_check_14-2.7.8-1PGDG.rhel8.x86_64.rpm
this is a static code analysis tool for PL/pgSQL, PostgreSQL''s procedural language. It helps identify issues in PL/pgSQL code such as errors, potential bugs, and inefficiencies before execution.
Ajay => Explore

plprofiler_14-server-4.2.2-1PGDG.rhel8.x86_64.rpm
this is an extension for profiling PL/pgSQL functions. It helps in identifying performance bottlenecks in database functions by collecting execution statistics, which can be useful for optimizing complex queries.
Ajay => Explore

table_version_14-1.11.1-1PGDG.rhel8.noarch.rpm
helps manage and track changes in table data over time by providing versioning capabilities. It is particularly useful for auditing or maintaining a historical record of data modifications. This extension allows users to version tables efficiently without requiring custom triggers or complex logic.
Ajay => Explore

✅ General-Purpose Extensions
Extension	Purpose
pg_stat_statements	Tracks execution statistics of all SQL statements (used for performance tuning).
auto_explain	Logs execution plans of slow queries automatically.
pg_hint_plan	Allows query planner hints to influence execution plan (useful when the planner doesn’t pick the best plan).
uuid-ossp	Provides functions to generate UUIDs (uuid_generate_v4() etc).
pgcrypto	Provides cryptographic functions for hashing, encryption, etc.

✅ Performance / Indexing
Extension	Purpose
btree_gin	Enables GIN indexing for B-tree-like operators.
btree_gist	Allows B-tree indexable types to be used with GiST indexes.
pg_trgm	Enables trigram-based indexing for fast LIKE/ILIKE/fuzzy searches.
fuzzystrmatch	Functions for approximate string matching.
hypopg	Simulates hypothetical indexes (used for "what-if" planning).
bloom - Implements Bloom filter indexes for queries with many combined WHERE conditions, offering space-efficient indexes when traditional methods are too large.

✅ Partitioning / Table Management
Extension	Purpose
pg_partman	Automates time- or ID-based partitioning.
tablefunc	Provides functions like crosstab() (pivot tables).
pg_repack	Reorganizes tables/indexes to reduce bloat without locks.

✅ Monitoring / Introspection
Extension	Purpose
pg_stat_kcache	Gather statistics about physical disk access and CPU consumption done by backends.
pg_stat_monitor	Enhanced replacement for pg_stat_statements (by Percona).
pg_buffercache	Shows what data is in PostgreSQL’s shared buffer cache.
pg_visibility	Shows visibility map and heap tuple visibility.
pg_freespacemap	Views free space available in each table block.

✅ Logical / Physical Replication
Extension	Purpose
pglogical	Logical replication plugin with rich features like conflict resolution, DDL replication.
wal2json	Output plugin for logical decoding (WAL -> JSON), used with Kafka pipelines etc.
test_decoding	Simple output plugin for logical replication (mainly for testing).

✅ Foreign Data Wrappers (FDW)
Extension	Purpose
postgres_fdw	Connects to another PostgreSQL server.
mysql_fdw	Connects to MySQL databases.
oracle_fdw	Connects to Oracle databases.
odbc_fdw	Generic ODBC-based FDW for various DBs.
file_fdw	Access CSV or other flat files as foreign tables.
multicorn	Python-based FDW framework (supports MongoDB, Elasticsearch, etc.).

✅ Time-Series / Advanced Use Cases
Extension	Purpose
timescaledb	Adds time-series database features (hypertables, compression, etc.).
pipelineDB	SQL-based stream processing (now merged into TimescaleDB).
zombodb	Full-text search integration with Elasticsearch.

✅ Security / Auditing
Extension	Purpose
pgaudit	Provides detailed session and/or object audit logging.
sepgsql	Adds SELinux integration for access control.
pg_statement_rollback	Adds SAVEPOINT rollback on errors in psql.

🔧 Utility / Admin Tools
Extension	Purpose
plpgsql_check	Static analysis and linting for PL/pgSQL functions.
pg_cron	Run cron jobs directly in PostgreSQL (e.g., periodic VACUUM, ANALYZE, etc.).
pg_proctab	Returns system process information (top-like view inside Postgres).

Total 25
---------

```

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
sudo cat /etc/passwd | grep postgres

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
repo1-retention-full=2 # keep last 2 full backups
repo1-retention-diff=7 # keep last 3 differential backups
repo1-retention-archive=2 # keep 2 days of WALs
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
pg1-path = /var/lib/postgresql/16/main
pg1-host = ryzen9
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

## [Managing PITR (Restore)](https://pgbackrest.org/command.html#command-restore)
```
# restore to a target time with delta (time & size)
pgbackrest --stanza=ryzen9 --delta --log-level-console=info --type=time "--target=2025-05-12 15:30:00" restore

select pg_wal_replay_resume();

# temp restore a backup set on different directory
pgbackrest --stanza=pg-cls2 --pg1-path=/tmp/pgsql --set=20250920-103557F restore

# started the temp restored copy on different port
/usr/pgsql-16/bin/pg_ctl -D /tmp/pgsql -o "-p 5431" start

# Stop temp running postgres service
/usr/pgsql-16/bin/pg_ctl -D /tmp/pgsql stop

# Reinit standby cluster node to a particular timeline
pgbackrest --stanza=pg-cls2 --type=standby --target-timeline=16 --force restore

```

## To expire existing backups
```
pgbackrest --stanza=ryzen9 expire
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

# [Migrate using AWS Schema Conversion Tool (SCT)](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Source.SQLServer.ToPostgreSQL.html)

# AWS Database Migration Service

# [Babelfish for Aurora PostgreSQL](https://aws.amazon.com/rds/aurora/babelfish/)


