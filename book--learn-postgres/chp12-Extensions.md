
# Extending the Database - The Extension Ecosystem
-----------------------------------------------------

-> An extension is a packaged set of files that can be installed in the cluster
    in order to provide more functionalities.

-> The extensions are installed in the database and not in the cluster.

-> The extensions are managed strictly through specific commands that install, deploy,
    load, and upgrade the extension as a whole.

-> The main aim of the extension is to provide a common interface for administrating
    new features.

-> Default installed "contrib" package provides a set of extensions that are
    maintained by the PostgreSQL developers.

-> Extensions are published through a global repository called "PGXN" (PostgreSQL Extension Network).


The Extension Ecosystem
------------------------

-> The PGXN can be considered as having following functions -
    -> A search engine
    -> An extension package manager
    -> An application programming interface (API)
    -> A client tool

-> A search engine allows users to search the PGXN repository for extensions.
-> An Extension package manager allows users to download and install extensions.
-> An application programming interface (API) defines how applications can interact with the
    package manager and search engine, and therefore how a client can be built.

-> There are 2 main clients available for PGXN -
    -> The pgxn client
    -> The PGXN website

-> PostgreSQL Extension System (PGXS) defines basic set of rules that an extension must follow.

-> PGXS provides a sample makefile that every extension should use to provide a set of common
    functionalities to install, upgrade, and remove the extension.

-> To find the sample makefile

|------------$ pg_config --pgxs
/usr/lib/postgresql/16/lib/pgxs/src/makefiles/pgxs.mk


Extension Components
-----------------------------------------------------------

-> The "control file" defines metadata of extension and is used to install, upgrade, and remove
    the extension.

-> The "script file" is a SQL file that contains statements to create database objects that are
    required by the extension.

-> The script file can also load other files that complete the extension, like a shared library.

-> When asked to install an extension, the system inspects the control file to check if its already installed,
    and if not, it installs the extension by executing the script file in "share directory".

-> To find share directory of the cluster, use the following command -

|------------$ pg_config --sharedir
/usr/share/postgresql/16

-> The extension must be selectively installed in every database that needs it.

-> If an extension is need for all future databases, then it should be installed in the template database.


The Control File
--------------------------------------------------------------

-> The control file is a text file where we specify "directives", which are instructions and metadata
    to let PostgreSQL handle the extension installation.

-> Each directive has a name and a value.

-> The most common directives are as follows-

# check/install contrib package
dpkg -l | grep postgresql-contrib  # Debian/Ubuntu
rpm -qa | grep postgresql-contrib  # RHEL/CentOS

sudo apt install postgresql-contrib  # Debian/Ubuntu
sudo apt install postgresql-plperl
sudo yum install postgresql-contrib  # RHEL/CentOS


-- check available extensions
SELECT * FROM pg_available_extensions WHERE name LIKE '%contrib%';

-- List installed extensions
select * from pg_extension;




*/ 

```
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

✅ Partitioning / Table Management
Extension	Purpose
pg_partman	Automates time- or ID-based partitioning.
tablefunc	Provides functions like crosstab() (pivot tables).
pg_repack	Reorganizes tables/indexes to reduce bloat without locks.

✅ Monitoring / Introspection
Extension	Purpose
pg_stat_kcache	Tracks OS-level metrics like CPU time per query (requires Linux perf stats).
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
```