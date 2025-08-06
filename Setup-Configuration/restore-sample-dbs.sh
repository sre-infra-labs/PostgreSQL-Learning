export PGPASSWORD='<password>';

# Restore Sample Database from *.tar File
  # assuming ~/.pgpass file is present along with peer authentication is enabled
/PostgreSQL/14/bin> pg_restore -Cv -d postgres /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/dvdrental.tar
/PostgreSQL/14/bin> pg_restore -Cv -d postgres /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/forumdb.tar

# Backup database
(base) saanvi@ryzen9:~$ pg_dump -U postgres -h localhost -d forumdb -F tar -f /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/forumdb.tar

# Backup smartpostgres database from internet
  # https://smartpostgres.com/posts/announcing-early-access-to-the-stack-overflow-sample-database-download-for-postgres/
pg_dump -U readonly -W '511e0479-4d35-49ab-98b1-c3a9d69796f4' -h query.smartpostgres.com -d stackoverflow -F tar -f ~/Downloads/stackoverflow.tar
pg_dump --dbname=postgresql://readonly:511e0479-4d35-49ab-98b1-c3a9d69796f4@query.smartpostgres.com/stackoverflow -F tar -f ~/Downloads/stackoverflow.tar


# Restore StackOverflow in custom tablespace
saanvi@ryzen9:~/Github/PostgreSQL-Learning$ mkdir /vm-storage-01/pg_data
saanvi@ryzen9:~/Github/PostgreSQL-Learning$ mkdir /vm-storage-02/pg_data
saanvi@ryzen9:~/Github/PostgreSQL-Learning$ sudo chown postgres:postgres /vm-storage-01/pg_data
saanvi@ryzen9:~/Github/PostgreSQL-Learning$ sudo chown postgres:postgres /vm-storage-02/pg_data

postgres=# create tablespace vm_storage_01 owner postgres location '/vm-storage-01/pg_data';
postgres=# create tablespace vm_storage_02 owner postgres location '/vm-storage-02/pg_data';

postgres=# create tablespace e_pg_data owner postgres location 'E:\\PG_Data\\\data';

# create 2 stackoverflow dbs. [stackoverflow2010] - 6 gb size || [stackoverflow] - 117 gb size 
postgres=# create database stackoverflow2010 with owner=postgres;
postgres=# create database stackoverflow with owner=postgres TABLESPACE=vm_storage_01;
postgres=# create database stackoverflow_large with owner=postgres TABLESPACE=vm_storage_02;

# Check existing tablespaces
postgres=# SELECT spcname AS tablespace_name, pg_tablespace_location(oid) AS location FROM pg_tablespace;

# Check if databases are set to expected tablespaces
postgres=# SELECT datname, pg_tablespace.spcname AS default_tablespace FROM pg_database LEFT JOIN pg_tablespace ON pg_database.dattablespace = pg_tablespace.oid;

# Query to get table level tablespace configuration
SELECT relname AS table_name, pg_tablespace.spcname AS tablespace
FROM pg_class
LEFT JOIN pg_tablespace ON pg_class.reltablespace = pg_tablespace.oid
WHERE relname = 'your_table_name';


# set tablespace explicitly if required
postgres=# ALTER DATABASE my_database SET default_tablespace = vm_storage_01;


postgres=# set default_tablespace=vm_storage_01;
SET
postgres=# 

# Sample restore commands
/PostgreSQL/14/bin> pg_restore -h localhost -U postgres -d stackoverflow_large /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/stackoverflow.tar
/PostgreSQL/14/bin> pg_restore -h localhost -U postgres -d stackoverflow -v 'E:\Share\stackoverflow-postgres-2010\dump-stackoverflow2010.sql'

# Actual restore commands
/PostgreSQL/14/bin> pg_restore -h localhost -U postgres -d stackoverflow2010 -v '/stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/stackoverflow-postgres-2010-v0.1/dump-stackoverflow2010-202408101013.sql'
/PostgreSQL/14/bin> pg_restore -h localhost -U postgres -d stackoverflow -v '/stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/stackoverflow-postgres-2024-v0.1/dump-stackoverflow-202408100709.sql'

# Actual restore commands on Windows
pg_restore -h localhost -U postgres -d stackoverflow2010 -v "S:\Backup\stackoverflow-postgres-2010-v0.1\dump-stackoverflow2010-202408101013.sql"
pg_restore -h localhost -U postgres -d stackoverflow -v "S:\Backup\stackoverflow-postgres-2024-v0.1\dump-stackoverflow-202408100709.sql"


# restore postgres_air from pg_dump backup
pg_restore -h localhost -d postgres_air -U postgres /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/postgres_air/postgres_air_2023.backup
pg_restore -h officelaptop -d postgres_air -U postgres /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/postgres_air/postgres_air_2023.backup

# method 02: simply execute following query in Query Window
/stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/postgres_air/postgres_air_2023.sql


alter database forumdb refresh collation version;
alter database dvdrental refresh collation version;