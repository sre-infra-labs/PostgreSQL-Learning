# Get Read-Only copy of StackOverflow for Postgres
-- [How to Query SmartPostgreSQL.com](https://smartpostgres.com/how-to-use-query-smartpostgres-com/)
-- [Database Diagram](https://sedeschema.github.io/)
-- [Documentation about Schema](https://meta.stackexchange.com/questions/2677/database-schema-documentation-for-the-public-data-dump-and-sede/2678#2678)

-- [Download StackOverflow for Postgres](https://smartpostgres.com/go/getstack)
  -- https://smartpostgres.com/posts/announcing-early-access-to-the-stack-overflow-sample-database-download-for-postgres/

## Dump `stackoverflow2013` database schema & data for backward compatibility. Later restore it on another server.
```bash
# Make backup directory
mkdir -p /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/stackoverflow2013
cd /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/stackoverflow2013

# Dump database schema only. Include indexes, functions etc but not data.
pg_dump --schema-only --no-owner --no-privileges -d stackoverflow2013 > stackoverflow2013--schema.sql

# Dump database data only. Loop through each table, and dump data into separate *.sql files
mkdir table_data
for tbl in $(psql -d stackoverflow2013 -t -c "select tablename from pg_tables where schemaname = 'public'"); do
    pg_dump --data-only --no-owner --no-privileges -t $tbl -d stackoverflow2013 >> table_data/$tbl.sql;
    #pg_dump --data-only --inserts --no-owner --no-privileges -t $tbl -d stackoverflow2013 >> table_data/$tbl.sql;
done

# Restore database on new server
psql -c 'create database stackoverflow2013;'
psql -d stackoverflow2013 -f stackoverflow2013--schema.sql
for tbl in table_data/*.sql; do
    psql -d stackoverflow2013 -f $tbl;
done
```


## Dump database on remote host to file
```
pg_dump -U username -h hostname databasename > dump.sql
```

# Backup/Restore of StackOverflow2013
## Take plain compressed backup of stackoverflow2013
```
# backup database
pg_dump -v -Z 9 -x -f /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/stackoverflow2013.sql.gz stackoverflow2013

# copy to blog website
scp /tmp/backups/stackoverflow2013.sql.gz admin@blogsite:/home/admin/public_html/share-with-others/

# Download the backup from web
https://ajaydwivedi.com/share-with-others/stackoverflow2013.sql.gz
```
## Restore backup
```
# Unzip backup file & restore database
cd /tmp/backups/
gunzip -k stackoverflow2013.sql.gz

psql>

-- create database
create database stackoverflow2013;
-- import from backup file
\i /tmp/backups/stackoverflow2013.sql

```





