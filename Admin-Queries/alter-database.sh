# Below worked for me
export PGPASSWORD='<password>'

# connect, and create a database
psql -h localhost -d postgres -U postgres
create database DBA2 with owner = 'postgres';

# rename database
ALTER DATABASE "StackOverflow" RENAME TO stackoverflow;

# change table schema
alter table users set schema dbo;

#

Server -> sqlmonitor.ajaydwivedi.com,25432
Login -> rreddy
Commands for adding sysadmin -> 

postgres=# create role rreddy with login password 'YourPasswordHere';
postgres=# alter role rreddy with superuser;
postgres=# GRANT ALL PRIVILEGES ON DATABASE stackoverflow TO rreddy;

# Add entry in pg_hba.conf file also


Connection command ->
psql -h sqlmonitor.ajaydwivedi.com -p 25432 -U rreddy -d stackoverflow -W

psql -U rreddy -d stackoverflow -h localhost -W