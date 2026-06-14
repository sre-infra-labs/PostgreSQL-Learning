# Environment Variables for Data Migration Scripts

## Quick Setup

```bash
# 1. Source the setup script
source setup-migration-env.sh

# 2. Edit the password variables:
# Edit setup-migration-env.sh and change:
#   - SOURCE_MSSQLPASSWORD (SQL Server password)
#   - TARGET_PGPASSWORD (PostgreSQL password)

# 3. Run any migration script
python migrate-[badges]-table--mssql-2-postgresql.py
python migrate-[users]-table--mssql-2-postgresql.py
```

## Required Environment Variables

### SQL Server (SOURCE)

| Variable | Default | Purpose | Example |
|----------|---------|---------|---------|
| `SOURCE_MSSQLHOST` | `localhost` | SQL Server hostname/IP | `192.168.1.100` |
| `SOURCE_MSSQLDATABASE` | `StackOverflow2013` | Database name | `StackOverflow2013` |
| `SOURCE_MSSQLUSER` | `sa` | Login user | `sa` |
| `SOURCE_MSSQLPASSWORD` | *(none)* | **REQUIRED** Password | `YourPassword123` |

### PostgreSQL (TARGET)

| Variable | Default | Purpose | Example |
|----------|---------|---------|---------|
| `TARGET_PGHOST` | `localhost` | PostgreSQL hostname/IP | `192.168.1.50` |
| `TARGET_PGPORT` | `5432` | Port (optional) | `5432` |
| `TARGET_PGDATABASE` | `stackoverflowmini` | Database name | `stackoverflow2013` |
| `TARGET_PGUSER` | `postgres` | Login user | `postgres` |
| `TARGET_PGPASSWORD` | *(none)* | **REQUIRED** Password | `YourPassword123` |

## Setup Methods

### Method 1: Edit setup-migration-env.sh (Recommended)

```bash
# Edit the file
nano setup-migration-env.sh

# Change these lines:
# Line 24: export SOURCE_MSSQLPASSWORD="YourSQLServerPassword"
# Line 48: export TARGET_PGPASSWORD="YourPostgreSQLPassword"

# Then source it:
source setup-migration-env.sh
```

### Method 2: Set variables directly

```bash
export SOURCE_MSSQLHOST="localhost"
export SOURCE_MSSQLDATABASE="StackOverflow2013"
export SOURCE_MSSQLUSER="sa"
export SOURCE_MSSQLPASSWORD="YourSQLServerPassword"
export TARGET_PGHOST="localhost"
export TARGET_PGPORT="5432"
export TARGET_PGDATABASE="stackoverflow2013"
export TARGET_PGUSER="postgres"
export TARGET_PGPASSWORD="YourPostgreSQLPassword"
```

### Method 3: .env file approach

```bash
# Create .env file
cat > .env << EOF
SOURCE_MSSQLHOST=localhost
SOURCE_MSSQLDATABASE=StackOverflow2013
SOURCE_MSSQLUSER=sa
SOURCE_MSSQLPASSWORD=YourSQLServerPassword
TARGET_PGHOST=localhost
TARGET_PGPORT=5432
TARGET_PGDATABASE=stackoverflow2013
TARGET_PGUSER=postgres
TARGET_PGPASSWORD=YourPostgreSQLPassword
EOF

# Load it in your script or use:
set -a; source .env; set +a
```

## Security Notes

⚠️ **DO NOT commit passwords to Git!**

- Add `.env` to `.gitignore`
- Never hardcode passwords in scripts
- Use `.pgpass` file for PostgreSQL (see below)
- Use Windows Credential Manager for SQL Server

## PostgreSQL .pgpass File (Recommended)

Create `~/.pgpass` for secure PostgreSQL authentication:

```bash
# Format: hostname:port:database:username:password
echo "localhost:5432:stackoverflow2013:postgres:YourPassword" >> ~/.pgpass
chmod 600 ~/.pgpass
```

Then remove `TARGET_PGPASSWORD` from environment variables.

## Verify Configuration

```bash
# Test SQL Server connection
python -c "
import pyodbc
conn_str = (
    'DRIVER={ODBC Driver 18 for SQL Server};'
    f'SERVER=localhost;'
    f'DATABASE=StackOverflow2013;'
    f'UID=sa;'
    f'PWD=YourPassword;'
    'TrustServerCertificate=yes;'
)
pyodbc.connect(conn_str)
print('✓ SQL Server connection OK')
"

# Test PostgreSQL connection
python -c "
import psycopg2
psycopg2.connect(host='localhost', dbname='stackoverflow2013', user='postgres', password='YourPassword')
print('✓ PostgreSQL connection OK')
"
```

## Migration Scripts Available

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

## Run All Migrations

```bash
source setup-migration-env.sh
for script in migrate-*.py; do
    echo "Running $script..."
    python "$script"
done
```
