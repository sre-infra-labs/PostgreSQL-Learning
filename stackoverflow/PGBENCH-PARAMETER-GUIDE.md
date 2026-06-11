# pgbench Parameter Guide - Complete Reference

## 📋 Overview

The `run-workload-test-pgbench.sh` script provides flexible command-line parameters for both PostgreSQL connection settings and workload configuration, supporting local and remote database testing with multiple authentication methods.

---

## 🚀 Quick Start

```bash
# Default: localhost, stackoverflow2013, 8×500
./run-workload-test-pgbench.sh

# Show help and all options
./run-workload-test-pgbench.sh --help

# Custom workload (local)
./run-workload-test-pgbench.sh --threads 4 --iterations 250

# Remote database with .pgpass
./run-workload-test-pgbench.sh -d mydb -h 192.168.1.100 -U postgres

# Remote database with password
./run-workload-test-pgbench.sh -d mydb -h 192.168.1.100 -U postgres -W 'password'
```

---

## 📝 Parameters

### Connection Parameters (PostgreSQL compatible)

#### `-d, --database NAME`
- Database name to connect to
- Default: **stackoverflow2013**
- Range: Any valid PostgreSQL database name
- Example: `-d mydb` or `--database production_db`

#### `-h, --host HOST`
- PostgreSQL server hostname or IP address
- Default: **localhost**
- Range: Any hostname, IP address (IPv4/IPv6), or Unix domain socket
- Examples: `-h 192.168.1.100`, `-h remote.example.com`, `-h /tmp` (socket)

#### `-p, --port PORT`
- PostgreSQL server port number
- Default: **5432** (PostgreSQL default)
- Range: 1-65535
- Example: `-p 5433` for non-standard port

#### `-U, --username USER`
- Database user/role to connect as
- Default: **current system user**
- Range: Any valid PostgreSQL user
- Examples: `-U postgres`, `-U appuser`, `-U readonly`

#### `-W, --password PASS`
- Database password (for authentication)
- Default: **None** (uses .pgpass or no password)
- Range: Any string
- Security: Only use in secure environments or scripts
- Example: `-W 'mypassword123'`
- Note: See authentication methods section below

### Workload Parameters

#### `--threads NUM`
- Number of concurrent database connections
- Default: **8**
- Range: Any positive integer (1, 2, 4, 8, 16, 32, etc.)
- Impact: Higher threads = more concurrent load
- Example: `--threads 16` for heavy load testing

#### `--iterations NUM`
- Number of transactions per thread
- Default: **500**
- Range: Any positive integer (10, 100, 500, 1000, etc.)
- Impact: Higher iterations = more total queries
- Example: `--iterations 1000` for longer test duration

### Other Options

#### `--help`
- Display complete usage information and examples
- Exits after showing help
- Example: `./run-workload-test-pgbench.sh --help`

---

## 🔐 Authentication Methods

### 1. Using .pgpass File (Recommended)
Most secure method - no password in command line history

**Setup:**
```bash
# Create ~/.pgpass file with format: host:port:database:user:password
echo "192.168.1.100:5432:mydb:postgres:mypassword" >> ~/.pgpass
chmod 600 ~/.pgpass
```

**Usage:**
```bash
./run-workload-test-pgbench.sh -d mydb -h 192.168.1.100 -U postgres
# Password read from ~/.pgpass automatically
```

### 2. Command-line Password (-W flag)
Quick method for scripting, use cautiously

**Usage:**
```bash
./run-workload-test-pgbench.sh -d mydb -h 192.168.1.100 -U postgres -W 'password123'
# Password passed via PGPASSWORD environment variable
# Cleared after test completes
```

### 3. No Password
Works with peer/trusted authentication

**Usage:**
```bash
./run-workload-test-pgbench.sh -d mydb -h localhost -U postgres
# Connects without password (must be configured in pg_hba.conf)
```

---

## 🎯 Common Use Cases

### 1. Local Smoke Test (Quick Validation)
```bash
./run-workload-test-pgbench.sh --threads 2 --iterations 50
# Database: localhost, stackoverflow2013
# Result: 100 total queries across 2 threads
# Time: < 1 minute
```

### 2. Local Standard Test (Default)
```bash
./run-workload-test-pgbench.sh
# Database: localhost, stackoverflow2013
# Result: 4,000 queries across 8 threads
# Time: 5-10 minutes
```

### 3. Remote Server - Light Test
```bash
./run-workload-test-pgbench.sh -d mydb -h staging.company.com -U appuser --threads 4 --iterations 100
# Database: staging.company.com, mydb
# Result: 400 queries across 4 threads
# Time: 2-5 minutes
```

### 4. Remote Server - Heavy Load Test
```bash
./run-workload-test-pgbench.sh \
  -d proddb \
  -h prod-db-1.company.com \
  -p 5433 \
  -U produser \
  --threads 16 \
  --iterations 1000
# Database: prod-db-1.company.com:5433, proddb
# Result: 16,000 queries across 16 threads
# Time: 15-30 minutes
```

### 5. Remote Server - With Password Authentication
```bash
./run-workload-test-pgbench.sh \
  -d mydb \
  -h 192.168.1.100 \
  -U postgres \
  -W 'SecurePassword123' \
  --threads 8
# Uses password authentication instead of .pgpass
# Result: 4,000 queries across 8 threads
```

### 6. Single-threaded Validation (No Concurrency)
```bash
./run-workload-test-pgbench.sh --threads 1 --iterations 500
# Result: 500 sequential queries
# Time: < 5 minutes
# Use: Verify functionality without concurrency
```

### 7. Custom Port and All Parameters
```bash
./run-workload-test-pgbench.sh \
  -d testdb \
  -h 192.168.100.50 \
  -p 5433 \
  -U testuser \
  -W 'testpassword' \
  --threads 12 \
  --iterations 750
# All parameters specified
# Result: 9,000 queries across 12 threads
```

---

## 📊 Workload Parameter Combinations

| Threads | Iterations | Total | Purpose |
|---------|-----------|-------|---------|
| 1 | 100 | 100 | Quick validation |
| 2 | 50 | 100 | Smoke test |
| 4 | 250 | 1,000 | Light load |
| 8 | 500 | 4,000 | Standard test |
| 16 | 500 | 8,000 | Heavy load |
| 16 | 1,000 | 16,000 | Stress test |
| 32 | 1,000 | 32,000 | High stress |

---

## 🔗 Connection + Workload Combinations

| Scenario | Command |
|----------|---------|
| Local development | `./run-workload-test-pgbench.sh --threads 2 --iterations 100` |
| Local standard | `./run-workload-test-pgbench.sh` |
| Remote with .pgpass | `./run-workload-test-pgbench.sh -d db -h host.com -U user --threads 4` |
| Remote with password | `./run-workload-test-pgbench.sh -d db -h host.com -U user -W pass --threads 4` |
| Custom port | `./run-workload-test-pgbench.sh -h host.com -p 5433 -U user --threads 8` |
| Full specification | `./run-workload-test-pgbench.sh -d db -h host -p 5433 -U user -W pass --threads 16 --iterations 1000` |

---

## ✅ Verification Examples

Test that parameters work correctly:

```bash
# Show help
./run-workload-test-pgbench.sh --help

# Verify local defaults
./run-workload-test-pgbench.sh 2>&1 | grep "Database:\|Threads:\|Host:"

# Verify remote connection settings
./run-workload-test-pgbench.sh -d mydb -h 192.168.1.100 -U postgres 2>&1 | grep "Database:\|Host:\|User:"

# Verify workload parameters
./run-workload-test-pgbench.sh --threads 4 --iterations 250 2>&1 | grep "Threads:\|Total queries"
```

---

## 🔄 Parameter Order

Parameters work in any order (both connection and workload parameters):

```bash
# All equivalent
./run-workload-test-pgbench.sh --threads 4 --iterations 250
./run-workload-test-pgbench.sh --iterations 250 --threads 4

# Connection + workload parameters can be mixed
./run-workload-test-pgbench.sh --threads 8 -d mydb -h host.com --iterations 500
./run-workload-test-pgbench.sh -d mydb --iterations 500 -h host.com --threads 8
./run-workload-test-pgbench.sh -h host.com --threads 8 --iterations 500 -d mydb
```

---

## 📄 Output Example - Local Connection

```
==========================================
PostgreSQL Workload Testing - pgbench
==========================================
Connection Settings:
  Database: stackoverflow2013
  Host: localhost (default)
  Port: 5432 (default)
  User: current user (default)
  Authentication: .pgpass or no password

Workload Settings:
  Threads: 4
  Iterations per thread: 250
  Total queries to execute: 1000
  Function: usp_randomq()

Test SQL:
SELECT * FROM usp_randomq() LIMIT 1;

==========================================
Starting workload test...
==========================================

pgbench (16.14 (Ubuntu 16.14-1.pgdg24.04+1))
pgbench: pghost: /var/run/postgresql pgport: 5432 nclients: 4 nxacts: 250
...
```

## � Output Example - Remote Connection

```
==========================================
PostgreSQL Workload Testing - pgbench
==========================================
Connection Settings:
  Database: proddb
  Host: prod-db-1.company.com
  Port: 5433
  User: produser
  Authentication: password provided

Workload Settings:
  Threads: 8
  Iterations per thread: 500
  Total queries to execute: 4000
  Function: usp_randomq()

Test SQL:
SELECT * FROM usp_randomq() LIMIT 1;

==========================================
Starting workload test...
==========================================

pgbench (16.14 (Ubuntu 16.14-1.pgdg24.04+1))
pgbench: pghost: prod-db-1.company.com pgport: 5433 nclients: 8 nxacts: 500
...
✓ Workload test completed successfully!
```

---

## 🔄 Mixing Connection and Workload Parameters

You can combine any connection parameters with any workload parameters:

```bash
# Database + workload
./run-workload-test-pgbench.sh -d mydb --threads 4

# Host + port + workload
./run-workload-test-pgbench.sh -h 192.168.1.100 -p 5433 --iterations 500

# Full connection + workload
./run-workload-test-pgbench.sh \
  -d proddb \
  -h prod-server.com \
  -p 5433 \
  -U produser \
  -W 'password' \
  --threads 16 \
  --iterations 1000

# Parameters can be in any order
./run-workload-test-pgbench.sh --threads 8 -d mydb -h host.com -U user --iterations 500
./run-workload-test-pgbench.sh -h host.com --iterations 500 -d mydb --threads 8 -U user
```

---

## 📚 Related Documentation

- **WORKLOAD-TESTING-GUIDE.md** - Complete testing guide with examples
- **README-PostgreSQL-Conversion.md** - Project overview
- Official pgbench documentation: `man pgbench`

---

## ✅ Summary Table

| Parameter | Short | Long | Default | Purpose |
|-----------|-------|------|---------|---------|
| Database | -d | --database | stackoverflow2013 | Which database to test |
| Host | -h | --host | localhost | Where to connect |
| Port | -p | --port | 5432 | Connection port |
| User | -U | --username | current user | Login user |
| Password | -W | --password | (none) | Authentication |
| Threads | | --threads | 8 | Concurrent connections |
| Iterations | | --iterations | 500 | Queries per thread |

---

**Status**: ✅ PRODUCTION READY

All parameters (connection and workload) tested and verified. Supports local and remote PostgreSQL databases with flexible authentication methods.
