# Get Read-Only copy of StackOverflow for Postgres
-- [How to Query SmartPostgreSQL.com](https://smartpostgres.com/how-to-use-query-smartpostgres-com/)
-- [Database Diagram](https://sedeschema.github.io/)
-- [Documentation about Schema](https://meta.stackexchange.com/questions/2677/database-schema-documentation-for-the-public-data-dump-and-sede/2678#2678)

-- [Download StackOverflow for Postgres](https://smartpostgres.com/go/getstack)
  -- https://smartpostgres.com/posts/announcing-early-access-to-the-stack-overflow-sample-database-download-for-postgres/

## Connection Details for Smart Postgres
```
Server: query.smartpostgres.com
Username: readonly
Password: 511e0479-4d35-49ab-98b1-c3a9d69796f4
```

## Take backup of smartpostgres.com stackoverflow copy
```
pg_dump --dbname=postgresql://readonly:511e0479-4d35-49ab-98b1-c3a9d69796f4@query.smartpostgres.com/stackoverflow -F tar -f ~/Downloads/stackoverflow.tar
```

# Backup/Restore of StackOverflow2013
## Take plain compressed backup of stackoverflow2013
```
# backup database
pg_dump -v -Z 9 -x -f /tmp/backups/stackoverflow2013.sql.gz stackoverflow2013

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





