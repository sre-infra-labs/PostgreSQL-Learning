# Get Read-Only copy of StackOverflow for Postgres
-- [How to Query SmartPostgreSQL.com](https://smartpostgres.com/how-to-use-query-smartpostgres-com/)
-- [Database Diagram](https://sedeschema.github.io/)
-- [Documentation about Schema](https://meta.stackexchange.com/questions/2677/database-schema-documentation-for-the-public-data-dump-and-sede/2678#2678)

-- [Download StackOverflow for Postgres](https://smartpostgres.com/go/getstack)
  -- https://smartpostgres.com/posts/announcing-early-access-to-the-stack-overflow-sample-database-download-for-postgres/

## Dump `stackoverflow2013` database schema & data for backward compatibility. Later restore it on another server.
```bash
# Make backup directory
mkdir -p /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/stackoverflowmini
cd /stale-storage/Softwares/PostgreSQL/PostgreSQL-Sample-Dbs/stackoverflowmini

# Dump database schema only. Include indexes, functions etc but not data.
pg_dump --schema-only --no-owner --no-privileges -d stackoverflow2013 > stackoverflow2013--schema.sql

# Dump database data only. Loop through each table, and dump data into separate *.sql files
mkdir table_data
for tbl in $(psql -d stackoverflow2013 -t -c "select tablename from pg_tables where schemaname = 'public'"); do
    pg_dump --data-only --no-owner --no-privileges -t $tbl -d stackoverflow2013 >> table_data/$tbl.sql;
    #pg_dump --data-only --inserts --no-owner --no-privileges -t $tbl -d stackoverflow2013 >> table_data/$tbl.sql;
done

# Restore database on new server
psql -c 'create database stackoverflowmini;'
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

---

# Data Migration from SQL Server to PostgreSQL

## Environment Variables Setup

For migrating data from SQL Server to PostgreSQL using the `migrate-[*]-table--mssql-2-postgresql.py` scripts, set up environment variables:

### Quick Setup

```bash
# 1. Create .env file with your credentials
cat > .env << EOF
SOURCE_MSSQLHOST=localhost
SOURCE_MSSQLDATABASE=StackOverflow2013
SOURCE_MSSQLUSER=sa
SOURCE_MSSQLPASSWORD=your_password
TARGET_PGHOST=localhost
TARGET_PGPORT=5432
TARGET_PGDATABASE=stackoverflow2013
TARGET_PGUSER=postgres
TARGET_PGPASSWORD=your_password
EOF

# 2. Load environment variables
source .env

# 3. Run any migration script
python migrate-[users]-table--mssql-2-postgresql.py 2>&1 | tee logs/migrate-\[users\]-table--mssql-2-postgresql.py.log
python migrate-[badges]-table--mssql-2-postgresql.py 2>&1 | tee logs/migrate-\[badges\]-table--mssql-2-postgresql.py.log
# ... etc for other tables
```

### Required Environment Variables

**SQL Server (SOURCE):**
```bash
export SOURCE_MSSQLHOST="localhost"           # SQL Server hostname/IP
export SOURCE_MSSQLDATABASE="StackOverflow2013"  # Database name
export SOURCE_MSSQLUSER="sa"                  # Login user
export SOURCE_MSSQLPASSWORD="your_password"   # REQUIRED: Your SQL Server password
```

**PostgreSQL (TARGET):**
```bash
export TARGET_PGHOST="localhost"              # PostgreSQL hostname/IP
export TARGET_PGPORT="5432"                   # PostgreSQL port (default: 5432)
export TARGET_PGDATABASE="stackoverflow2013"  # Database name
export TARGET_PGUSER="postgres"               # Login user
export TARGET_PGPASSWORD="your_password"      # REQUIRED: Your PostgreSQL password
```

### Setup Method

**Create and use .env file:**
```bash
# Create .env file
cat > .env << EOF
SOURCE_MSSQLHOST=localhost
SOURCE_MSSQLDATABASE=StackOverflow2013
SOURCE_MSSQLUSER=sa
SOURCE_MSSQLPASSWORD=your_password
TARGET_PGHOST=localhost
TARGET_PGPORT=5432
TARGET_PGDATABASE=stackoverflow2013
TARGET_PGUSER=postgres
TARGET_PGPASSWORD=your_password
EOF

# Load it
source .env
```

### Available Migration Scripts

- `migrate-[badges]-table--mssql-2-postgresql.py`
- `migrate-[comments]-table--mssql-2-postgresql.py`
- `migrate-[linktypes]-table--mssql-2-postgresql.py`
- `migrate-[postlinks]-table--mssql-2-postgresql.py`
- `migrate-[posts]-table--mssql-2-postgresql.py`
- `migrate-[posttypes]-table--mssql-2-postgresql.py`
- `migrate-[tags]-table--mssql-2-postgresql.py`
- `migrate-[users]-table--mssql-2-postgresql.py`
- `migrate-[votes]-table--mssql-2-postgresql.py`
- `migrate-[votetypes]-table--mssql-2-postgresql.py`

### Run All Migrations

```bash
source .env
for script in migrate-*.py; do
    echo "Running $script..."
    python "$script" 2>&1 | tee "logs/$script.log"
done
```

### Security Notes

⚠️ **DO NOT commit passwords to Git:**
- Add `.env` to `.gitignore`
- Use `.pgpass` file for PostgreSQL (see [PostgreSQL documentation](https://www.postgresql.org/docs/current/libpq-pgpass.html))
- Use Windows Credential Manager for SQL Server credentials

**For PostgreSQL .pgpass:**
```bash
# Create ~/.pgpass file
echo "localhost:5432:stackoverflow2013:postgres:your_password" >> ~/.pgpass
chmod 600 ~/.pgpass

# Then remove TARGET_PGPASSWORD from environment variables
unset TARGET_PGPASSWORD
```

### Verify Configuration

```bash
# Test SQL Server connection
python -c "
import pyodbc, os
conn_str = (
    'DRIVER={ODBC Driver 18 for SQL Server};'
    f'SERVER={os.getenv(\"SOURCE_MSSQLHOST\")};'
    f'DATABASE={os.getenv(\"SOURCE_MSSQLDATABASE\")};'
    f'UID={os.getenv(\"SOURCE_MSSQLUSER\")};'
    f'PWD={os.getenv(\"SOURCE_MSSQLPASSWORD\")};'
    'TrustServerCertificate=yes;'
)
pyodbc.connect(conn_str)
print('✓ SQL Server connection OK')
"

# Test PostgreSQL connection
python -c "
import psycopg2, os
psycopg2.connect(
    host=os.getenv('TARGET_PGHOST'),
    dbname=os.getenv('TARGET_PGDATABASE'),
    user=os.getenv('TARGET_PGUSER'),
    password=os.getenv('TARGET_PGPASSWORD'),
    sslmode='require'
)
print('✓ PostgreSQL connection OK')
"
```

### More Information

See `MIGRATION-ENV-REFERENCE.md` for detailed documentation on environment variables, setup methods, and troubleshooting.

---

# Migration Setup: SQL Server to PostgreSQL

## Environment Variables for Migration Scripts

The `migrate-[table]-table--mssql-2-postgresql.py` scripts require environment variables to connect to both SQL Server (source) and PostgreSQL (target) databases.

### Quick Setup

```bash
# 1. Create .env file with your credentials
cat > .env << EOF
SOURCE_MSSQLHOST=localhost
SOURCE_MSSQLDATABASE=StackOverflow2013
SOURCE_MSSQLUSER=sa
SOURCE_MSSQLPASSWORD=YourPassword
TARGET_PGHOST=localhost
TARGET_PGPORT=5432
TARGET_PGDATABASE=stackoverflow2013
TARGET_PGUSER=postgres
TARGET_PGPASSWORD=YourPassword
EOF

# 2. Load environment variables
source .env

# 3. Run any migration script
python migrate-[badges]-table--mssql-2-postgresql.py
python migrate-[users]-table--mssql-2-postgresql.py
```

### Required Environment Variables

**SQL Server (SOURCE)**
```bash
export SOURCE_MSSQLHOST="localhost"              # SQL Server hostname/IP
export SOURCE_MSSQLDATABASE="StackOverflow2013"  # Database name
export SOURCE_MSSQLUSER="sa"                     # Login user
export SOURCE_MSSQLPASSWORD="YourPassword"       # REQUIRED
```

**PostgreSQL (TARGET)**
```bash
export TARGET_PGHOST="localhost"           # PostgreSQL hostname/IP
export TARGET_PGPORT="5432"                # Port (optional)
export TARGET_PGDATABASE="stackoverflow2013" # Database name
export TARGET_PGUSER="postgres"            # Login user
export TARGET_PGPASSWORD="YourPassword"    # REQUIRED
```

### Setup Method

**Create and use .env file:**
```bash
# Create .env file
cat > .env << EOF
SOURCE_MSSQLHOST=localhost
SOURCE_MSSQLDATABASE=StackOverflow2013
SOURCE_MSSQLUSER=sa
SOURCE_MSSQLPASSWORD=YourPassword
TARGET_PGHOST=localhost
TARGET_PGPORT=5432
TARGET_PGDATABASE=stackoverflow2013
TARGET_PGUSER=postgres
TARGET_PGPASSWORD=YourPassword
EOF

# Load variables
source .env
```

### Available Migration Scripts

```bash
python migrate-[badges]-table--mssql-2-postgresql.py
python migrate-[comments]-table--mssql-2-postgresql.py
python migrate-[linktypes]-table--mssql-2-postgresql.py
python migrate-[postlinks]-table--mssql-2-postgresql.py
python migrate-[posts]-table--mssql-2-postgresql.py
python migrate-[posttypes]-table--mssql-2-postgresql.py
python migrate-[tags]-table--mssql-2-postgresql.py
python migrate-[users]-table--mssql-2-postgresql.py
python migrate-[votes]-table--mssql-2-postgresql.py
python migrate-[votetypes]-table--mssql-2-postgresql.py
```

### Run All Migrations

```bash
source setup-migration-env.sh
for script in migrate-*.py; do
    echo "Running $script..."
    python "$script"
done
```

### Security Best Practices

⚠️ **DO NOT commit passwords to Git!**
- Add `.env` to `.gitignore`
- Use `.pgpass` file for PostgreSQL authentication
- Use Windows Credential Manager for SQL Server

See `MIGRATION-ENV-REFERENCE.md` for detailed documentation.


