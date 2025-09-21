# `pg_dump` Help
```
|------------$ pg_dump --help
pg_dump dumps a database as a text file or to other formats.

Usage:
  pg_dump [OPTION]... [DBNAME]

General options:
  -f, --file=FILENAME          output file or directory name
  -F, --format=c|d|t|p         output file format (custom, directory, tar,
                               plain text (default))
  -j, --jobs=NUM               use this many parallel jobs to dump
  -v, --verbose                verbose mode
  -Z, --compress=METHOD[:DETAIL] compress as specified. Value 0-9.

Options controlling the output content:
  -a, --data-only              dump only the data, not the schema
  -c, --clean                  clean (drop) database objects before recreating
  -C, --create                 include commands to create database in dump
  -n, --schema=PATTERN         dump the specified schema(s) only
  -N, --exclude-schema=PATTERN do NOT dump the specified schema(s)
  -O, --no-owner               skip restoration of object ownership in plain-text format
  -s, --schema-only            dump only the schema, no data
  -t, --table=PATTERN          dump only the specified table(s)
  -T, --exclude-table=PATTERN  do NOT dump the specified table(s)
  -x, --no-privileges          do not dump privileges (grant/revoke)
  --column-inserts             dump data as INSERT commands with column names
  --disable-dollar-quoting     disable dollar quoting, use SQL standard quoting
  --disable-triggers           disable triggers during data-only restore
  --enable-row-security        enable row security (dump only content user has access to)
  --exclude-table-and-children=PATTERN
                               do NOT dump the specified table(s), including child and partition tables
  --exclude-table-data=PATTERN do NOT dump data for the specified table(s)
  --exclude-table-data-and-children=PATTERN
                               do NOT dump data for the specified table(s), including child and partition tables
  --extra-float-digits=NUM     override default setting for extra_float_digits
  --if-exists                  use IF EXISTS when dropping objects
  --include-foreign-data=PATTERN
                               include data of foreign tables on foreign servers matching PATTERN
  --inserts                    dump data as INSERT commands, rather than COPY
  --no-unlogged-table-data     do not dump unlogged table data
  --on-conflict-do-nothing     add ON CONFLICT DO NOTHING to INSERT commands
  --quote-all-identifiers      quote all identifiers, even if not key words
  --rows-per-insert=NROWS      number of rows per INSERT; implies --inserts
  --table-and-children=PATTERN dump only the specified table(s), including child and partition tables

Connection options:
  -d, --dbname=DBNAME      database to dump
  -h, --host=HOSTNAME      database server host or socket directory
  -p, --port=PORT          database server port number
  -U, --username=NAME      connect as specified database user
  -w, --no-password        never prompt for password
  -W, --password           force password prompt (should happen automatically)
  --role=ROLENAME          do SET ROLE before dump

If no database name is supplied, then the PGDATABASE environment
variable value is used.
```

# Dumping a single database
```
-- Dumping a single database with default format
    -- -F, --format=c|d|t|p         output file format (custom, directory, tar, plain text (default))
pg_dump stackoverflow2010 > /tmp/stackoverflow2010.sql

-- Dump single database from cross engine migration. Expect longer backup time
pg_dump --inserts stackoverflow2010 > /tmp/stackoverflow2010.sql
pg_dump --column-inserts stackoverflow2010 > /tmp/stackoverflow2010.sql
pg_dump --column-inserts -f /tmp/stackoverflow2010.sql stackoverflow2010

-- Create create database script is required
pg_dump --create --column-inserts stackoverflow2010 > /tmp/stackoverflow2010.sql
```

# Dumping a large database table by table in plain format
```
#!/bin/bash
DB=stackoverflow
BACKUP_DIR=/tmp/backups/$DB
mkdir -p "$BACKUP_DIR"

tables=$(psql -At -d $DB -c "SELECT tablename FROM pg_tables WHERE schemaname='public';")

for tbl in $tables; do
    echo "Dumping $tbl ..."
    pg_dump -v -Z 9 -x -t "$tbl" $DB > "$BACKUP_DIR/$tbl.sql.gz"
done
```

# Restore a single database
```
-- Create a database for restore. By default, database creation does not happen in backup script.
psql -c 'create database stackoverflow2010_copy with owner postgres;'

psql -U postgres -d stackoverflow2010_copy
\i /tmp/stackoverflow2010.sql

-- set search_path which is erased during restore to avoid issues.
select pg_catalog.set_config('search_path', 'public', "$user", false);
```

# Compression
```
# backup with no compression
pg_dump -Z 9 stackoverflow2010 > /tmp/stackoverflow2010.sql

# backup with gzip compression
pg_dump -Z 9 -f /tmp/stackoverflow2010_compressed.sql.gz stackoverflow2010
```

# Dump formats and pg_restore
```
# backup with custom format
pg_dump -Fc --create --verbose -Z 9 -f /tmp/pg_backup/stackoverflow2010.bkp stackoverflow2010

# restore database from backup
psql -c 'drop database stackoverflow2010_copy;'
pg_restore -C --verbose-d postgres /tmp/pg_backup/stackoverflow2010.bkp

# create a shell database and restore from backup
pg_restore --verbose -d stackoverflow2010_copy /tmp/pg_backup/stackoverflow2010.bkp

# extract backup content into sql file for inspection
pg_restore /tmp/pg_backup/stackoverflow2010.bkp -f /tmp/pg_backup/stackoverflow2010.sql


# backup in directory format
pg_dump -Fd --verbose -f /tmp/pg_backup.d stackoverflow2010
# restore backup from directory format
pg_restore --verbose -d stackoverflow2010_copy /tmp/pg_backup.d


# back in tar format (uncompressed backup)
pg_dump -Ft --verbose -f /tmp/pg_backup/stackoverflow2010.tar stackoverflow2010
# Check tar file
tar -tvf /tmp/pg_backup/stackoverflow2010.tar
```


# Performing a Selective Restore

## Get directory type dump
pg_dump -Fd -Z 9 -v -f /tmp/backup__postgres_air postgres_air

## Get content list
  >Get source, version, is_compressed, backup date
pg_restore --list /tmp/backup__postgres_air

3562; 0 6904635 TABLE DATA postgres_air passenger postgres
│     │ │       │          │            │         │
│     │ │       │          │            │         └─ Owner of the table: postgres
│     │ │       │          │            └─────────── Table name: passenger
│     │ │       │          └──────────────────────── Schema: postgres_air
│     │ │       └─────────────────────────────────── Object type: TABLE DATA (the data, not the definition)
│     │ └─────────────────────────────────────────── Object OID: 6904635
│     └───────────────────────────────────────────── Object ID of the object type (table data in this case). 
└─────────────────────────────────────────────────── Internal id of object inside dump: 3562


## Save Table of Content (ToC) in a file
pg_restore --list /tmp/backup__postgres_air > /tmp/backup__postgres_air__TOC.txt

## Edit the ToC file
vim /tmp/backup__postgres_air__TOC.txt

## Restore database [postgres_air] using new TOC file
pg_restore -C -d postgres -L /tmp/backup__postgres_air__TOC.txt /tmp/backup__postgres_air


# COPY Command
```
psql>

copy forum.categories to '/tmp/categories.bak.txt';
```

# IMPORT DATA FROM SQLSERVER TO POSTGRESQL
```
export MSSQLPASSWORD='YourStrongPasswordHere'

# BCP out data from sql server
  # Postgres COPY does not support multi character column delimiter, and any row delimiter.
rm -f /tmp/backups/users.bak.txt
bcp "SELECT top 100 * FROM dbo.users" queryout /tmp/backups/users.bak.txt -S localhost -d StackOverflow2013 -U sa -P $MSSQLPASSWORD -c -t "!!c!!" -r "!!r!!" -u

-C 65001

| Option      | Meaning                           |
| ----------- | --------------------------------- |
| `queryout`  | Export based on SQL query         |
| `-c`        | Use character format (text)       |
| `-C`        | Use character encoding UTF-8      |
| `-t"\t"`    | Use tab `\t` as field delimiter   |
| `-r"\n"`    | Use newline `\n` as row delimiter |
| `-S`        | SQL Server name (or IP + port)    |
| `-u`        | Trust Server Certificate          |
| `-U` / `-P` | SQL Server login credentials      |


# COPY FROM in PostgreSQL
psql>

\c scratchpad

CREATE TABLE public.users (
    id               INTEGER PRIMARY KEY,
    aboutme          TEXT,
    age              INTEGER,
    creationdate     TIMESTAMP NOT NULL,
    displayname      VARCHAR(40) NOT NULL,
    downvotes        INTEGER NOT NULL,
    emailhash        VARCHAR(40),
    lastaccessdate   TIMESTAMP NOT NULL,
    location         VARCHAR(100),
    reputation       INTEGER NOT NULL,
    upvotes          INTEGER NOT NULL,
    views            INTEGER NOT NULL,
    websiteurl       VARCHAR(200),
    accountid        INTEGER
);

\COPY users (
  id,
  aboutme,
  age,
  creationdate,
  displayname,
  downvotes,
  emailhash,
  lastaccessdate,
  location,
  reputation,
  upvotes,
  views,
  websiteurl,
  accountid
)
FROM '/tmp/backups/users.bak.txt'
WITH (
  FORMAT csv,
  DELIMITER ',',
  HEADER false,
  QUOTE '"',
  NULL ''
);
```

# Physical Backup using `pg_basebackup`
```
# perform physical backup into directory /backup
pg_basebackup -D /backup/data -l 'My physical backup' -v -h localhost \
        -p 5432 -U postgres -T /data/tablespaces/ts_b=/backup/tablespaces/ts_b \
        -T /data/tablespaces/ts_a=/backup/tablespaces/ts_a \
        -T /data/tablespaces/ts_c=/backup/tablespaces/ts_c

# verify the backup
pg_verifybackup /backup/data/

# Start the cloned cluster
pg_ctl -D /backup/data/ -o '-p 5433' start
```


