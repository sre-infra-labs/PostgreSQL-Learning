# Change Data Capture (CDC) Using Debezium and Kafka
- [Blog - How Patroni Addresses the Problem of the Logical Replication Slot Failover in a PostgreSQL Cluster](https://www.percona.com/blog/how-patroni-addresses-the-problem-of-the-logical-replication-slot-failover-in-a-postgresql-cluster/)
- [Patroni 2.1.0+ Doc - Replication slots](https://patroni.readthedocs.io/en/latest/dynamic_configuration.html#:~:text=slots%3A%20define%20permanent%20replication%20slots)
- [Blog - How we managed Postgres HA with Logical Replication using Patroni](https://medium.com/@PavankumarHarikar/how-we-managed-postgres-ha-with-logical-replication-using-patroni-1d31a6f6c9b0)
- [Youtube - Alexander Kukushkin. Failover of logical replication slots in Patroni](https://www.youtube.com/live/SllJsbPVaow?si=bjIlu-umeXKFeRlJ)
  - [Slidedeck](https://www.postgresql.eu/events/pgconfde2022/sessions/session/3745/slides/306/Implementing%20failover%20of%20logical%20replication%20slots%20in%20Patroni.pdf)
- [Debezium - PostgreSQL - Permissions](https://debezium.io/documentation/reference/3.4/connectors/postgresql.html#postgresql-permissions)

## Overview

Change Data Capture (CDC) is a design pattern that captures data changes at the source and propagates them to downstream systems in real-time. This document explains the CDC architecture using Debezium and Kafka with PostgreSQL as the source database.

**Updated**: 2026-05-11

## Architecture

Each CDC service runs in its own dedicated container on the shared `lab-network`, coexisting with
the Patroni HA cluster (pg1–pg4). Ports 5433–5437 are reserved for the Patroni cluster; the CDC
PostgreSQL source uses 5438.

```
Host (macOS)
│
├── Docker Network: lab-network (172.18.0.0/16)
│   │
│   ├─ Patroni HA Cluster (reserved IPs — do not reuse)
│   │  ├── 172.18.0.9  ← Keepalived Replica VIP  (floats to sync standby)
│   │  ├── 172.18.0.10 ← Keepalived Primary VIP  (floats to Patroni leader)
│   │  ├── pg1  (172.18.0.11)  host port 5433
│   │  ├── pg2  (172.18.0.12)  host port 5434
│   │  ├── pg3  (172.18.0.13)  host port 5435
│   │  ├── pg-bouncer (172.18.0.20)  host port 5436
│   │  └── pg4  (172.18.0.14)  host port 5437
│   │
│   └─ CDC Stack
│      │
│      ├── cdc-postgres   (172.18.0.25)   PostgreSQL 15 CDC source
│      │     container port 5432  →  host port 5438
│      │     wal_level=logical, publication: dbz_publication
│      │     replication slot: debezium_slot (pgoutput plugin)
│      │
│      ├── cdc-zookeeper  (172.18.0.21+)  Zookeeper (Kafka coordinator)
│      │     container port 2181  →  host port 2181
│      │     peer ports 2888/3888 (internal only)
│      │
│      ├── cdc-kafka      (172.18.0.21+)  Kafka broker
│      │     container port 9092  →  host port 29092
│      │
│      ├── cdc-debezium   (172.18.0.21+)  Debezium Connect (REST API)
│      │     container port 8083  →  host port 8083
│      │     connector: postgres-cdc-connector (postgres plugin)
│      │
│      ├── cdc-kafka-ui   (172.18.0.21+)  Kafka UI (Provectus)
│      │     container port 8080  →  host port 8080
│      │
│      └── cdc-pgadmin    (172.18.0.26)   pgAdmin 4 + pgBadger
│            container port 80    →  host port 5050
│            pgBadger web reports →  port 8888 (inside container)
│
└── Docker Bind-Mount Volumes  (~/cdc-volumes/)
      ├── postgres/data     — PostgreSQL data directory
      ├── postgres/logs     — PostgreSQL logs
      ├── postgres/config   — postgresql.conf, pg_hba.conf (read-only mounts)
      └── pgadmin/          — pgAdmin session/config persistence
```

### Port & Endpoint Summary

| Container | Image | Container IP | Internal Port | Host Port | Endpoint / Purpose |
|---|---|---|---|---|---|
| `cdc-postgres` | postgres:15 | 172.18.0.25 | 5432 | **5438** | PostgreSQL CDC source (`psql -h localhost -p 5438`) |
| `cdc-zookeeper` | confluentinc/cp-zookeeper | 172.18.0.21+ | 2181 | **2181** | Kafka coordination |
| `cdc-kafka` | confluentinc/cp-kafka | 172.18.0.21+ | 9092 | **29092** | Kafka broker (`localhost:29092`) |
| `cdc-debezium` | debezium/connect | 172.18.0.21+ | 8083 | **8083** | REST API `http://localhost:8083` |
| `cdc-kafka-ui` | provectuslabs/kafka-ui | 172.18.0.21+ | 8080 | **8080** | Web UI `http://localhost:8080` |
| `cdc-pgadmin` | dpage/pgadmin4 | 172.18.0.26 | 80 | **5050** | pgAdmin UI `http://localhost:5050` |

> **Note:** `cdc-zookeeper`, `cdc-kafka`, `cdc-debezium`, and `cdc-kafka-ui` are deployed via a
> single `docker-compose` file; their IPs are sequentially assigned by Docker starting at
> `172.18.0.21`.

### CDC Data Flow

```
cdc-postgres (172.18.0.25:5432)
    │  WAL logical replication (pgoutput plugin)
    │  Publication: dbz_publication  |  Slot: debezium_slot
    ▼
cdc-debezium (172.18.0.21+:8083)
    │  Reads WAL changes → converts to JSON Kafka messages
    │  Connector: postgres-cdc-connector
    ▼
cdc-kafka (172.18.0.21+:9092)   ←── coordinated by cdc-zookeeper (:2181)
    │  Topics: postgres-cdc.public.users
    │          postgres-cdc.public.orders
    │          postgres-cdc.public.products
    ▼
Consumers: cdc-kafka-ui (browse), application clients (localhost:29092)
    ▼
Data Pipelines / Analytics / Cache / Data Warehousing
```

## How It Works

### 1. PostgreSQL Side (Source)

PostgreSQL has built-in **Logical Replication** capability that allows:
- **WAL (Write-Ahead Log)** captures all database changes
- **Publication**: Defines which tables to replicate
- **Replication Slot**: Tracks changes so they aren't lost

Configuration required:
```sql
-- Enable logical replication in postgresql.conf
wal_level = logical

-- Create publication (what to capture)
CREATE PUBLICATION dbz_publication FOR ALL TABLES;

-- Create replication slot (where to capture from; name must match connector slot.name)
SELECT * FROM pg_create_logical_replication_slot('debezium_slot', 'pgoutput');

-- Set REPLICA IDENTITY on tables (needed for updates/deletes)
ALTER TABLE table_name REPLICA IDENTITY FULL;
```

#### Connect to PostgreSQL
```
# view saved passwords
ansible-vault view sensitive-values --vault-password-file=vault-pass

# connect to postgresql using docker
docker exec -it cdc-postgres bash
su - postgres
psql

# connect directly
export PGPASSWORD=$PGPWD_PERSONAL
psql -h localhost -p 5438 -U postgres
```


### 2. Debezium Connector

Debezium is a distributed platform that captures changes from databases.

**PostgreSQL Connector Workflow:**
1. Connects to PostgreSQL using replication user
2. Reads from the replication slot
3. Decodes changes using pgoutput plugin
4. Converts database events to Kafka messages
5. Publishes to Kafka topics (one per table)

**Connector Configuration (actual values used in this project):**
```json
{
  "name": "postgres-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "cdc-postgres",
    "database.port": "5432",
    "database.user": "replication",
    "database.password": "***",
    "database.dbname": "cdc_db",
    "database.server.name": "postgres-cdc",
    "topic.prefix": "postgres-cdc",
    "plugin.name": "pgoutput",
    "publication.name": "dbz_publication",
    "slot.name": "debezium_slot",
    "table.include.list": "public.users,public.orders,public.products",
    "snapshot.mode": "initial"
  }
}
```

### 3. Kafka

Kafka acts as the **message broker** that:
- Receives CDC events from Debezium
- Stores them durably on disk
- Allows multiple consumers to read independently
- Provides event history and replay capability

**Topics Created (format: `{topic.prefix}.{schema}.{table}`):**
- `postgres-cdc.public.users` - Changes to users table
- `postgres-cdc.public.orders` - Changes to orders table
- `postgres-cdc.public.products` - Changes to products table

**Internal Debezium topics (bookkeeping, not CDC data):**
- `my_connect_configs` - Connector configuration storage
- `my_connect_offsets` - Tracks which WAL positions have been consumed
- `my_connect_statuses` - Connector/task status information

Each topic stores 3 types of messages:
- **INSERT** - New row created
- **UPDATE** - Row values changed
- **DELETE** - Row removed

### 4. Message Format

Debezium uses a standard message format for all database changes:

```json
{
  "schema": {...},
  "payload": {
    "op": "c",  // c=create, u=update, d=delete, r=read
    "ts_ms": 1234567890,
    "before": {...},  // Previous values (for update/delete)
    "after": {...},   // New values (for insert/update)
    "source": {
      "version": "2.5.1",
      "connector": "postgresql",
      "name": "postgres-cdc",
      "db": "cdc_db",
      "schema": "public",
      "table": "users",
      "txId": 123,
      "lsn": 456,
      "xmin": null
    },
    "transaction": {
      "id": 123,
      "total_order": 1,
      "data_collection_order": 1
    }
  }
}
```

## Implementation in This Project

### Unified Kafka Ecosystem Container

To simplify deployment, we run multiple services in a coordinated Docker Compose setup:

```yaml
services:
  zookeeper:
    - Coordinates Kafka cluster
    - Stores metadata
    - Port: 2181

  kafka:
    - Message broker
    - Stores CDC events
    - Port: 9092 (internal), 29092 (exposed)

  debezium-connect:
    - CDC connector service
    - Reads from PostgreSQL
    - REST API on port 8083

  kafka-ui:
    - Web UI for monitoring
    - View topics and messages
    - Port: 8080
```

### PostgreSQL Source Container

- PostgreSQL 15 with CDC enabled
- Pre-configured with logical replication
- Publication and replication slot created automatically
- Test tables (users, orders, products) with sample data

### pgAdmin Container

- Database management GUI
- Access PostgreSQL databases
- Monitor replication status
- View logs and configurations

## Deployment & Access Points

### Service Ports & Access

| Service | Port | URL | Purpose |
|---------|------|-----|---------|
| **PostgreSQL** | 5438 | localhost:5438 | CDC source database |
| **pgAdmin** | 5050 | http://localhost:5050 | Database management GUI |
| **Zookeeper** | 2181 | localhost:2181 | Kafka coordination |
| **Kafka Broker** | 29092 | localhost:29092 | Message broker (external) |
| **Kafka Internal** | 9092 | kafka:9092 | Message broker (internal) |
| **Debezium** | 8083 | http://localhost:8083 | Connector REST API |
| **Kafka UI** | 8080 | http://localhost:8080 | Web monitoring interface |

### Credentials

Passwords are stored in the Ansible Vault. Fetch them with:

```bash
# View all credentials
ansible-vault view sensitive-values --vault-password-file=vault-pass

# Extract individual passwords into shell variables
export PG_SUPERUSER_PASSWORD=$(ansible-vault view sensitive-values --vault-password-file=vault-pass | grep PG_SUPERUSER_PASSWORD | awk '{print $2}' | tr -d '"')
export PG_REPLICATION_PASSWORD=$(ansible-vault view sensitive-values --vault-password-file=vault-pass | grep PG_REPLICATION_PASSWORD | awk '{print $2}' | tr -d '"')
export PGADMIN_DEFAULT_PASSWORD=$(ansible-vault view sensitive-values --vault-password-file=vault-pass | grep PGADMIN_DEFAULT_PASSWORD | awk '{print $2}' | tr -d '"')
```

```
PostgreSQL:
  - Host: localhost, Port: 5438
  - Admin User: postgres, Password: $PG_SUPERUSER_PASSWORD
  - Database: cdc_db
  - Replication User: replication, Password: $PG_REPLICATION_PASSWORD
  - App User: cdc_app, Password: $PG_APP_USER_PASSWORD

pgAdmin:
  - URL: http://localhost:5050
  - Email: admin@cdc-learning.local
  - Password: $PGADMIN_DEFAULT_PASSWORD
```

## Step-by-Step: Deploy Everything

### Step 1: Deploy Full Stack

```bash
cd ~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka

# Run the full deployment
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass
```

This deploys:
- Docker network (lab-network: 172.18.0.0/16)
- Zookeeper (port 2181)
- Kafka Broker (port 29092 external, 9092 internal)
- Debezium Connect (port 8083)
- Kafka UI (port 8080)
- PostgreSQL (port 5438)
- pgAdmin (port 5050)

**Expected output**: All 6 containers running, 3 Kafka topics created

### Step 2: Verify All Services Are Running

```bash
# Check containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Should show:
# cdc-pgadmin         Up ... 0.0.0.0:5050->80/tcp
# cdc-postgres        Up ... 0.0.0.0:5438->5432/tcp
# cdc-debezium        Up ... 0.0.0.0:8083->8083/tcp
# cdc-kafka-ui        Up ... 0.0.0.0:8080->8080/tcp
# cdc-kafka           Up ... 0.0.0.0:29092->9092/tcp
# cdc-zookeeper       Up ... 0.0.0.0:2181->2181/tcp
```

## Step-by-Step: Connect Debezium to PostgreSQL (Complete CDC Setup)

### PostgreSQL Permissions Setup (Debezium Requirements)

> **Source**: [Debezium Docs — Setting up permissions](https://debezium.io/documentation/reference/3.4/connectors/postgresql.html#postgresql-permissions)

Debezium requires a PostgreSQL user with specific privileges to stream changes.
Rather than granting superuser access, create a **dedicated replication user** with the minimum required privileges.

#### 1. Create the Replication User

The user must have `REPLICATION` and `LOGIN` privileges:

```sql
-- Create the dedicated Debezium replication user
CREATE ROLE replication REPLICATION LOGIN PASSWORD 'your_password';

-- Grant access to the target database (required for initial snapshot)
GRANT CONNECT ON DATABASE cdc_db TO replication;
```

#### 2. Grant SELECT for Initial Snapshot

Debezium reads all existing rows during the initial snapshot.
The replication user needs `SELECT` on all captured tables:

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication;

-- Cover tables created in the future
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO replication;
```

#### 3. Create Publication (pgoutput plugin)

Debezium uses the `pgoutput` logical decoding plugin, which requires a PostgreSQL **publication**.
A publication must be created by a user who owns (or has shared ownership of) the tables.

**Option A — Superuser creates the publication (simplest — used by this project):**

```sql
-- Run as superuser (postgres). This is what the Ansible playbook does.
CREATE PUBLICATION dbz_publication FOR ALL TABLES;
```

**Option B — Let Debezium manage the publication (requires shared table ownership):**

If `publication.autocreate.mode = filtered` and you want Debezium to create/manage
the publication itself, the replication user must co-own the tables via a replication group:

```sql
-- Step 1: Create a shared replication group role
CREATE ROLE replication_group;

-- Step 2: Add the original table owner to the group (typically postgres superuser)
GRANT replication_group TO postgres;

-- Step 3: Add the Debezium replication user to the group
GRANT replication_group TO replication;

-- Step 4: Transfer table ownership to the group
ALTER TABLE public.users    OWNER TO replication_group;
ALTER TABLE public.orders   OWNER TO replication_group;
ALTER TABLE public.products OWNER TO replication_group;
```

#### 4. Allow Replication in pg_hba.conf

Add entries to `pg_hba.conf` to permit the Debezium connector host to connect for replication:

```
# Local socket
local   replication     replication                             trust
# IPv4 localhost
host    replication     replication   127.0.0.1/32              scram-sha-256
# IPv6 localhost
host    replication     replication   ::1/128                   scram-sha-256
# Docker lab-network (cdc-debezium at 172.18.0.21+ → cdc-postgres at 172.18.0.25)
host    replication     replication   172.18.0.0/16             scram-sha-256
```

> The `172.18.0.0/16` line covers Docker-internal connections from `cdc-debezium`
> to `cdc-postgres` over `lab-network`.

#### Summary — What the Ansible Playbook Does Automatically

The playbook (`roles/postgres_source/tasks/main.yml`) handles all permission steps
automatically on every `ansible-playbook` run (idempotent):

| Debezium Requirement | Ansible Task |
|---|---|
| `REPLICATION LOGIN` user | `CREATE USER replication WITH REPLICATION LOGIN` |
| Encrypted password | `ALTER USER replication WITH ENCRYPTED PASSWORD '...'` |
| Database connect | `GRANT CONNECT ON DATABASE cdc_db TO replication` |
| Table SELECT (snapshot) | `GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication` |
| Publication | `CREATE PUBLICATION dbz_publication FOR ALL TABLES` (as superuser) |
| Replication slot | `SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput')` |
| `pg_hba.conf` | Rendered from `roles/postgres_source/templates/pg_hba.conf` |
| `REPLICA IDENTITY FULL` | `ALTER TABLE ... REPLICA IDENTITY FULL` on users/orders/products |

---

### Step 3: Verify PostgreSQL is Ready

```bash
# If required, use below command to restart services inside containers
for n in pg1 pg2 pg3 pg4; do echo "=== $n ===" && docker exec $n systemctl restart patroni | tail -3; done

# Test PostgreSQL connectivity
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "SELECT version();"

# Expected output:
# PostgreSQL 15.17 (Debian 15.17-1.pgdg13+1) ...

# Verify logical replication is enabled
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "SHOW wal_level;"

# Expected output: logical
```

#### If patroni cluster setup, then
```bash
root@pg1:/# patronictl show-config

loop_wait: 10
master_start_timeout: 300
maximum_lag_on_failover: 1048576
postgresql:
  parameters:
    max_replication_slots: 10
    max_wal_senders: 10
    synchronous_standby_names: ANY 2 (pg2, pg4)
    wal_level: logical
    wal_log_hints: 'on'
  use_pg_rewind: true
  use_slots: true
retry_timeout: 10
synchronous_mode: true
synchronous_mode_strict: false
synchronous_node_count: 1
ttl: 30
```

### Step 4: Check PostgreSQL Replication Configuration

```bash
# View replication user
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "SELECT usename, usecanlogin, usereplication FROM pg_user WHERE usename='replication';"

# View test tables
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public';"

# Expected tables:
# - users
# - orders
# - products
```

### Step 5: Test Debezium Connectivity

```bash
# Check Debezium REST API is responding
curl -s http://localhost:8083/ | head -20

# Expected: JSON response with Debezium version

# List existing connectors (should be empty initially)
curl -s http://localhost:8083/connectors | jq .
```

### Step 6: Create PostgreSQL Replication Publication & Slot (Manual Method)

**Note**: These are typically created by the Ansible playbook, but here's how to do it manually:

```bash
# Connect to PostgreSQL
docker exec cdc-postgres psql -U postgres -d cdc_db << 'EOF'

-- Create publication (defines what to replicate)
CREATE PUBLICATION dbz_publication FOR ALL TABLES;

-- Verify publication was created
SELECT * FROM pg_publication;

-- Create replication slot (tracks what Debezium has read)
SELECT * FROM pg_create_logical_replication_slot('debezium_slot', 'pgoutput');

-- Verify slot was created
SELECT * FROM pg_replication_slots;

-- Set REPLICA IDENTITY FULL (needed for UPDATE and DELETE operations)
ALTER TABLE public.users REPLICA IDENTITY FULL;
ALTER TABLE public.orders REPLICA IDENTITY FULL;
ALTER TABLE public.products REPLICA IDENTITY FULL;

-- Verify REPLICA IDENTITY
SELECT relname, pg_relation_replica_identity(oid)
FROM pg_class WHERE relkind='r' AND relname IN ('users', 'orders', 'products');

EOF
```

### Step 7: Create Debezium PostgreSQL Connector (CRITICAL - Enables CDC)

**This is the key step that connects Debezium to PostgreSQL and enables CDC.**

> **Note**: The Ansible playbook (`playbook-deploy-all.yml`) registers this connector automatically in its `post_tasks` block. Run the manual command below only if you need to re-register it after deletion.

```bash
# Fetch replication password from vault at runtime (never hardcode!)
PG_REPLICATION_PASSWORD=$(ansible-vault view sensitive-values --vault-password-file=vault-pass \
  | grep PG_REPLICATION_PASSWORD | awk '{print $2}' | tr -d '"')

# Delete existing connector if present (so re-runs apply fresh config)
curl -sf -X DELETE http://localhost:8083/connectors/postgres-cdc-connector 2>/dev/null || true
sleep 2

# Register the connector
curl -X POST http://localhost:8083/connectors \
  -H 'Content-Type: application/json' \
  -d "{
    \"name\": \"postgres-cdc-connector\",
    \"config\": {
      \"connector.class\": \"io.debezium.connector.postgresql.PostgresConnector\",
      \"database.hostname\": \"cdc-postgres\",
      \"database.port\": \"5432\",
      \"database.user\": \"replication\",
      \"database.password\": \"${PG_REPLICATION_PASSWORD}\",
      \"database.dbname\": \"cdc_db\",
      \"database.server.name\": \"postgres-cdc\",
      \"topic.prefix\": \"postgres-cdc\",
      \"plugin.name\": \"pgoutput\",
      \"publication.name\": \"dbz_publication\",
      \"slot.name\": \"debezium_slot\",
      \"table.include.list\": \"public.users,public.orders,public.products\",
      \"snapshot.mode\": \"initial\"
    }
  }"

# Expected response: JSON with "type":"source" and "tasks":[]
# The connector goes RUNNING within ~5 seconds
```

**Key configuration values explained:**
| Key | Value | Why |
|-----|-------|-----|
| `database.hostname` | `cdc-postgres` | Docker container name (resolves via Docker DNS) |
| `topic.prefix` | `postgres-cdc` | Prefixes all CDC topic names: `postgres-cdc.public.users` |
| `plugin.name` | `pgoutput` | Built-in PostgreSQL logical decoding plugin (no extra install needed) |
| `slot.name` | `debezium_slot` | Name of the replication slot that tracks WAL position |
| `publication.name` | `dbz_publication` | PostgreSQL publication listing which tables to capture |
| `snapshot.mode` | `initial` | Reads all existing rows first, then switches to streaming changes |

### Step 8: Verify Connector Was Created Successfully

```bash
# List all connectors
curl -s http://localhost:8083/connectors | jq .

# Expected output: ["postgres-cdc-connector"]

# Check connector status
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq .

# Expected: status should show "RUNNING" with no errors

# View connector tasks
curl -s http://localhost:8083/connectors/postgres-cdc-connector/tasks | jq .
```

### Step 9: Verify Kafka Topics Were Created

```bash
# List all Kafka topics
docker exec cdc-kafka kafka-topics --list --bootstrap-server localhost:9092

# Expected topics (6 total):
# __consumer_offsets        ← internal Kafka bookkeeping
# my_connect_configs        ← Debezium stores connector configs here
# my_connect_offsets        ← Debezium tracks WAL read position here
# my_connect_statuses       ← Debezium connector/task health here
# postgres-cdc.public.users     ← CDC events for the users table
# postgres-cdc.public.orders    ← CDC events for the orders table
# postgres-cdc.public.products  ← CDC events for the products table

# Check message count in each CDC topic (should be > 0 after snapshot)
docker exec cdc-kafka kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 --topic postgres-cdc.public.users --time -1
# Expected: postgres-cdc.public.users:0:<N>  where N = number of rows snapshotted
```

### Step 10: Insert Test Data into PostgreSQL

Now insert data and watch it flow through CDC:

```bash
# Table schemas (id SERIAL auto-generates; email/created_at have defaults):
# users    : id (auto), name VARCHAR(100), email VARCHAR(100), created_at TIMESTAMP
# orders   : id (auto), user_id INT, amount DECIMAL(10,2), created_at TIMESTAMP
# products : id (auto), name VARCHAR(100), price DECIMAL(10,2), created_at TIMESTAMP

# Insert test users
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "INSERT INTO public.users (name, email) VALUES
        ('John Doe', 'john@example.com'),
        ('Jane Smith', 'jane@example.com'),
        ('Bob Johnson', 'bob@example.com');"

# Insert test products
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "INSERT INTO public.products (name, price) VALUES
        ('Laptop', 999.99), ('Mouse', 29.99), ('Keyboard', 79.99);"

# Insert test orders (user_id references users.id)
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "INSERT INTO public.orders (user_id, amount) VALUES
        (1, 99.99), (2, 149.50), (1, 75.25);"

# Verify row counts
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "SELECT 'users' AS tbl, COUNT(*) FROM public.users
      UNION ALL SELECT 'orders', COUNT(*) FROM public.orders
      UNION ALL SELECT 'products', COUNT(*) FROM public.products;"
```

### Step 11: View CDC Events in Kafka (Real-time Data Capture)

**Option A: Using Kafka UI (Web Browser)**

```bash
# Open Kafka UI in browser
open http://localhost:8080

# In the UI:
# 1. Click on "Topics" in left menu
# 2. Select "postgres-cdc.public.users"
# 3. Click "Messages" tab at the top
# 4. Scroll through messages to see CDC events
#
# Each message key = row primary key (JSON)
# Each message value = CDC envelope with:
# - "op": "r" (read/snapshot), "c" (create), "u" (update), "d" (delete)
# - "before": Previous row values (for update/delete; null for insert)
# - "after": New row values (for insert/update; null for delete)
# - "source": PostgreSQL metadata (table, LSN, transaction ID, timestamp)
```

**Option B: Using Command Line**

```bash
# View messages from users topic (from the beginning, max 5 messages)
docker exec cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic postgres-cdc.public.users \
  --from-beginning \
  --max-messages 5

# Check message count without reading content
docker exec cdc-kafka kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 --topic postgres-cdc.public.users --time -1
# Output: postgres-cdc.public.users:0:<count>
```

### Step 12: Test Real-Time CDC - Insert New Data and Watch It Flow

```bash
# Terminal 1: Start a Kafka consumer watching for new messages (leave running)
docker exec cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic postgres-cdc.public.users

# Terminal 2: Insert new data into PostgreSQL
# The Kafka consumer in Terminal 1 will show the CDC event within ~1 second!
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "INSERT INTO public.users (name, email) VALUES ('New User', 'newuser@example.com');"

# You should see a new message appear in Terminal 1 with:
# - "op": "c"  (create)
# - "after": {"id": <N>, "name": "New User", "email": "newuser@example.com", ...}
# - "before": null  (nothing existed before)
```

### Step 13: Test UPDATE and DELETE Operations

```bash
# UPDATE: change a user's email
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "UPDATE public.users SET email = 'newemail@example.com' WHERE name = 'John Doe';"

# In Kafka Terminal, you'll see a message with:
# - "op": "u"  (update)
# - "before": {"name": "John Doe", "email": "john@example.com", ...}
# - "after":  {"name": "John Doe", "email": "newemail@example.com", ...}
# Note: "before" is populated because REPLICA IDENTITY FULL is set on the table

# DELETE: remove a user
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "DELETE FROM public.users WHERE name = 'New User';"

# In Kafka Terminal:
# - "op": "d"  (delete)
# - "before": {"name": "New User", "email": "newuser@example.com", ...}
# - "after": null  (row no longer exists)
```

## Steps to Explore CDC (Hands-on Walkthrough)

This section guides you through the live CDC experience step by step. You will do an action in PostgreSQL, then see it immediately appear in Kafka — that is CDC in action.

### Explore Step 1 — Open the GUI Tools

Open these three URLs in your browser:

| Tool | URL | What You See |
|------|-----|-------------|
| **Kafka UI** | http://localhost:8080 | Topic list, message browser, consumer groups |
| **pgAdmin** | http://localhost:5050 | Database browser, query editor, replication status |
| **Debezium REST** | http://localhost:8083/connectors | Returns `["postgres-cdc-connector"]` |

In **Kafka UI** → click **Topics** in the left menu. You should see 7 topics including `postgres-cdc.public.users`, `postgres-cdc.public.orders`, `postgres-cdc.public.products`.

### Explore Step 2 — Inspect an Existing CDC Message

In **Kafka UI**:
1. Click `postgres-cdc.public.users` → **Messages** tab
2. You'll see JSON messages already there from the initial snapshot (the rows that existed when Debezium first connected)
3. Each message key = `{"schema":...,"payload":{"id":<N>}}` (the primary key)
4. Each message value contains a `payload` object with:
   - `"op": "r"` = read (initial snapshot)
   - `"before": null` (snapshot has no "before")
   - `"after": {"id":1, "name":"...", "email":"...", ...}` (current row data)
   - `"source": {"table":"users", "lsn":12345, ...}` (where in WAL this came from)

### Explore Step 3 — Trigger a Live INSERT

Open **two terminals** side by side:

**Terminal 1** (watch Kafka in real-time):
```bash
docker exec cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic postgres-cdc.public.users
```
Leave this running.

**Terminal 2** (insert into PostgreSQL):
```bash
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "INSERT INTO public.users (name, email) VALUES ('Charlie Brown', 'charlie@example.com');"
```

Within ~1 second, Terminal 1 shows a JSON message. Look for `"op":"c"` (create). The `"after"` field has the new row. `"before"` is `null`.

### Explore Step 4 — Trigger an UPDATE and See Before/After

In **Terminal 2**:
```bash
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "UPDATE public.users SET email = 'charlie.updated@example.com' WHERE name = 'Charlie Brown';"
```

Terminal 1 now shows `"op":"u"` (update):
- `"before"` → the OLD email `charlie@example.com`
- `"after"` → the NEW email `charlie.updated@example.com`

> **Why do we see "before"?** Because `ALTER TABLE public.users REPLICA IDENTITY FULL` was set. Without this, `"before"` would be null on UPDATE.

### Explore Step 5 — Trigger a DELETE

```bash
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "DELETE FROM public.users WHERE name = 'Charlie Brown';"
```

Terminal 1 shows `"op":"d"` (delete):
- `"before"` → the deleted row's data
- `"after"` → `null` (it's gone)

### Explore Step 6 — Verify the Replication Slot Advances

Each time Debezium reads WAL changes and commits them to Kafka, the replication slot position advances. You can watch this:

```bash
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "SELECT slot_name, active, confirmed_flush_lsn, restart_lsn
      FROM pg_replication_slots;"
```

`confirmed_flush_lsn` increases after each batch of changes. A stuck LSN means Debezium stopped consuming.

### Explore Step 7 — Check Message Count from CLI

```bash
# How many messages are in the users topic?
docker exec cdc-kafka kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 --topic postgres-cdc.public.users --time -1
# Output: postgres-cdc.public.users:0:<count>

# Read the last 5 messages in raw JSON
docker exec cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic postgres-cdc.public.users \
  --from-beginning --max-messages 5
```

### Explore Step 8 — Check Debezium Consumer Group Lag

Debezium is a Kafka consumer itself (it writes to Kafka, but also reads internal topics). Check its lag:

```bash
# List consumer groups
docker exec cdc-kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 --list

# Describe the main connect group (lag should be 0 = fully caught up)
docker exec cdc-kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe --group connect-cluster
```

A `LAG` of `0` means Debezium has processed all changes. A growing `LAG` means Debezium is falling behind.

### Explore Step 9 — Add a New Table and Watch it Get Captured Automatically

The connector uses `publication.name: dbz_publication` which was created as `FOR ALL TABLES`. This means **any new table automatically gets captured** — no connector restart needed.

```bash
# Create a new table in PostgreSQL
docker exec cdc-postgres psql -U postgres -d cdc_db -c "
  CREATE TABLE IF NOT EXISTS public.inventory (
    id SERIAL PRIMARY KEY,
    item VARCHAR(100),
    qty INT,
    updated_at TIMESTAMP DEFAULT NOW()
  );
  ALTER TABLE public.inventory REPLICA IDENTITY FULL;
  INSERT INTO public.inventory (item, qty) VALUES ('Pencil', 100), ('Notebook', 50);
"
```

In **Kafka UI** → Topics → refresh. You'll see `postgres-cdc.public.inventory` appear automatically with 2 messages. No configuration change was needed.

---

## Key Concepts

### Logical Replication Slot

A replication slot is a bookkeeper that tracks:
- Which changes have been sent to consumers
- Which changes can be discarded
- Prevention of WAL files being removed before delivery

### Publication

Defines which tables to replicate. Can be:
- ALL TABLES - Replicate all tables
- Specific tables - Only selected tables

### WAL Decoding

PostgreSQL's logical decoding converts WAL (binary format) into logical changes using plugins:
- **pgoutput** - Built-in plugin, used by Debezium
- **wal2json** - JSON format
- **decoding_json** - Alternative JSON format

### Snapshot vs CDC

- **Snapshot**: Initial full copy of all data (handled by Debezium)
- **CDC**: Continuous capture of changes after snapshot

Debezium handles both:
1. Initial snapshot: Reads all existing data from table
2. CDC phase: Reads from replication slot for changes

## Advantages of CDC Pattern

✅ **Real-time Data Propagation** - Changes immediately flow to downstream systems
✅ **Decoupling** - Source database doesn't know about consumers
✅ **Scalability** - Multiple consumers can independently consume changes
✅ **Durability** - Kafka stores changes permanently
✅ **Replayability** - Can replay changes from any point in time
✅ **Low Latency** - Event-driven architecture
✅ **Audit Trail** - Complete history of all changes

## Use Cases

1. **Data Warehousing** - Real-time data sync to data warehouse
2. **Analytics** - Stream changes to analytics platforms
3. **Caching** - Keep caches in sync with database
4. **Search** - Update search indexes (Elasticsearch, etc.)
5. **Microservices** - Event notifications between services
6. **Data Replication** - Sync data across databases
7. **Auditing** - Maintain change audit logs

## Complete Quick Reference Commands

### View Service Status

```bash
# Check all running containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check specific service logs
docker logs cdc-postgres | tail -50              # PostgreSQL
docker logs cdc-kafka | tail -50                 # Kafka
docker logs cdc-debezium | tail -50              # Debezium
docker logs cdc-kafka-ui | tail -50              # Kafka UI
docker logs cdc-pgadmin | tail -50               # pgAdmin
```

### PostgreSQL Management

```bash
# Connect to PostgreSQL
docker exec -it cdc-postgres psql -U postgres -d cdc_db

# Or directly with one command:
docker exec cdc-postgres psql -U postgres -d cdc_db -c "SELECT * FROM public.users;"

# View all replication slots
docker exec cdc-postgres psql -U postgres -d cdc_db -c "SELECT * FROM pg_replication_slots;"

# View publications
docker exec cdc-postgres psql -U postgres -d cdc_db -c "SELECT * FROM pg_publication;"

# View table REPLICA IDENTITY status
docker exec cdc-postgres psql -U postgres -d cdc_db -c \
  "SELECT relname, pg_relation_replica_identity(oid) FROM pg_class WHERE relkind='r';"
```

### Debezium Management

```bash
# List all connectors
curl -s http://localhost:8083/connectors | jq .

# Get connector status
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq .

# Get connector config
curl -s http://localhost:8083/connectors/postgres-cdc-connector/config | jq .

# Get connector tasks
curl -s http://localhost:8083/connectors/postgres-cdc-connector/tasks | jq .

# Get task status
curl -s http://localhost:8083/connectors/postgres-cdc-connector/tasks/0/status | jq .

# Pause connector
curl -X PUT http://localhost:8083/connectors/postgres-cdc-connector/pause

# Resume connector
curl -X PUT http://localhost:8083/connectors/postgres-cdc-connector/resume

# Delete connector
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-connector

# Restart connector
curl -X POST http://localhost:8083/connectors/postgres-cdc-connector/restart
```

### Kafka Topic Management

```bash
# List all topics
docker exec cdc-kafka kafka-topics --list --bootstrap-server localhost:9092

# Describe a topic (partition count, replication, leader)
docker exec cdc-kafka kafka-topics --describe \
  --bootstrap-server localhost:9092 --topic postgres-cdc.public.users

# Check message count for each CDC topic
docker exec cdc-kafka kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 --topic postgres-cdc.public.users --time -1
docker exec cdc-kafka kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 --topic postgres-cdc.public.products --time -1

# Consume messages from beginning (max 10)
docker exec cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic postgres-cdc.public.users \
  --from-beginning \
  --max-messages 10

# Consume only NEW messages (live follow mode; Ctrl+C to stop)
docker exec cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic postgres-cdc.public.users

# Check consumer group lag
docker exec cdc-kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 --describe --group connect-cluster
```

## Troubleshooting Guide

### Connector Failed to Create

**Symptom**: Connector creation returns error

```bash
# Check Debezium logs
docker logs cdc-debezium | grep -i error

# Common causes:
# 1. PostgreSQL not responding
#    - Check: docker exec cdc-postgres psql -U postgres -d cdc_db -c "SELECT 1;"
#
# 2. Wrong credentials
#    - Verify: replication user exists and has correct password
#    - Check: docker exec cdc-postgres psql -U postgres -d cdc_db -c "SELECT * FROM pg_user WHERE usename='replication';"
#
# 3. Publication doesn't exist
#    - Check: docker exec cdc-postgres psql -U postgres -d cdc_db -c "SELECT * FROM pg_publication;"
#    - Create: docker exec cdc-postgres psql -U postgres -d cdc_db -c "CREATE PUBLICATION dbz_publication FOR ALL TABLES;"
#
# 4. Replication slot doesn't exist
#    - Check: docker exec cdc-postgres psql -U postgres -d cdc_db -c "SELECT * FROM pg_replication_slots;"
#    - Create: docker exec cdc-postgres psql -U postgres -d cdc_db -c "SELECT * FROM pg_create_logical_replication_slot('debezium_slot', 'pgoutput');"
```

### No Messages in Kafka Topics

**Symptom**: Topics exist but no messages appear after inserting data

```bash
# 1. Verify connector is running
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq .

# 2. Check if connector has an error
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq '.connector.state, .connector.trace'

# 3. Verify REPLICA IDENTITY is set correctly
docker exec cdc-postgres psql -U postgres -d cdc_db -c \
  "SELECT relname, pg_relation_replica_identity(oid) FROM pg_class WHERE relkind='r' AND relname IN ('users', 'orders', 'products');"

# 4. Check replication slot activity
docker exec cdc-postgres psql -U postgres -d cdc_db -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"

# 5. View Debezium connector logs
docker logs cdc-debezium | tail -100 | grep -i "users\|orders\|products\|error"
```

### Connector Stuck or Not Processing Data

**Symptom**: Connector runs but data changes don't appear in Kafka

```bash
# 1. Check connector task status
curl -s http://localhost:8083/connectors/postgres-cdc-connector/tasks/0/status | jq .

# 2. Verify snapshot phase completed
docker logs cdc-debezium | grep -i "snapshot\|snapshotting"

# 3. Check if connector is in paused state
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq '.connector.state'

# 4. Resume if paused
curl -X PUT http://localhost:8083/connectors/postgres-cdc-connector/resume

# 5. Restart connector if stuck
curl -X POST http://localhost:8083/connectors/postgres-cdc-connector/restart

# 6. Delete and recreate if all else fails
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-connector
# Then recreate using Step 7 commands
```

### High Replication Lag or Slow Message Propagation

**Symptom**: Data changes take a long time to appear in Kafka

```bash
# 1. Check replication slot lag
docker exec cdc-postgres psql -U postgres -d cdc_db -c \
  "SELECT slot_name, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) as lag_bytes FROM pg_replication_slots;"

# 2. Check PostgreSQL settings
docker exec cdc-postgres psql -U postgres -d cdc_db -c \
  "SHOW wal_keep_size; SHOW max_wal_senders; SHOW max_replication_slots;"

# 3. Monitor Debezium memory usage
docker stats cdc-debezium

# 4. Check Kafka broker lag
docker exec cdc-kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 --describe --group connect-cluster

# 5. Reduce connector task count or increase batch size (modify connector config)
curl -X PATCH http://localhost:8083/connectors/postgres-cdc-connector/config \
  -H "Content-Type: application/json" \
  -d '{"snapshot.isolation.mode": "read_uncommitted"}'
```

### Debezium Can't Connect to Kafka (TimeoutException / NodeExistsException)

**Symptom**: `Failed to connect to and describe Kafka cluster` or Kafka exits with `NodeExistsException`

This happens when containers are restarted individually out of order. Zookeeper retains a stale broker registration from the previous Kafka run.

**Fix - restart in correct order**:
```bash
# Step 1: Restart Zookeeper first (clears stale broker registration)
docker restart cdc-zookeeper

# Step 2: Wait for Zookeeper to be healthy, then start Kafka
sleep 10
docker start cdc-kafka

# Step 3: Wait for Kafka to be healthy, then start Debezium
sleep 15
docker start cdc-debezium

# Verify all are up
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "zookeeper|kafka|debezium"

# Verify Debezium connected successfully (look for "Herder started")
docker logs --tail 20 cdc-debezium | grep -E "ERROR|Herder started|group coordinator"
```

### Network Connectivity Issues

**Symptom**: Connector can't connect to PostgreSQL or Kafka

```bash
# 1. Verify containers are on same network
docker network inspect lab-network

# 2. Test PostgreSQL connectivity from Debezium container
docker exec cdc-debezium bash -c 'nc -zv cdc-postgres 5432'

# 3. Test Kafka connectivity from Debezium
docker exec cdc-debezium bash -c 'nc -zv kafka 9092'

# 4. Check container IPs
docker inspect cdc-postgres | jq '.[] | .NetworkSettings.Networks'
docker inspect cdc-kafka | jq '.[] | .NetworkSettings.Networks'
docker inspect cdc-debezium | jq '.[] | .NetworkSettings.Networks'
```

## Performance Tuning

### Connector Configuration for Better Performance

```json
{
  "config": {
    "snapshot.mode": "initial",
    "snapshot.isolation.mode": "read_uncommitted",
    "max.batch.size": 2048,
    "poll.interval.ms": 1000,
    "database.tcpKeepAlives": true,
    "heartbeat.interval.ms": 30000,
    "heartbeat.action.query": "INSERT INTO public.heartbeat (ts) VALUES (CURRENT_TIMESTAMP)"
  }
}
```

### Monitoring Metrics

```bash
# Check Debezium lag (how far behind PostgreSQL changes)
curl -s http://localhost:8083/connectors/postgres-cdc-connector/tasks/0/status | \
  jq '.task_state.millis_behind_source'

# Check Kafka consumer group lag
docker exec cdc-kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 --describe --group connect-cluster

# Monitor PostgreSQL WAL size
docker exec cdc-postgres psql -U postgres -d cdc_db -c \
  "SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0'));"
```

## Security Considerations

**Current Setup (Development)**:
- Credentials stored in Ansible Vault (`sensitive-values`, encrypted with vault-pass)
- View with: `ansible-vault view sensitive-values --vault-password-file=vault-pass`
- Replication user has minimal required permissions
- All ports bound to localhost (not exposed to network)
- Network isolation via Docker network (lab-network)

**For Production**:
- Use strong passwords for all users
- Implement SSL/TLS for PostgreSQL connections
- Restrict Debezium REST API access (use firewall/proxy)
- Rotate encryption keys regularly
- Monitor and audit all connector operations
- Use Kafka ACLs and authentication
- Implement role-based access control

## References

- Debezium Documentation: https://debezium.io/documentation/
- PostgreSQL Logical Replication: https://www.postgresql.org/docs/current/logical-replication.html
- Kafka Documentation: https://kafka.apache.org/documentation/
- pgoutput Plugin: https://www.postgresql.org/docs/current/logical-decoding-output-plugins.html

## Summary: End-to-End CDC Flow

### Data Flow Diagram

```
User Action (INSERT/UPDATE/DELETE)
        ↓
PostgreSQL WAL Records
        ↓
Logical Replication Slot (debezium_slot)
        ↓
pgoutput Plugin Decoding
        ↓
Debezium PostgreSQL Connector
        ↓
Kafka Producer (sends to broker)
        ↓
Kafka Broker (9092 internal, 29092 external)
        ↓
Kafka Topics (postgres-cdc.public.users, orders, products)
        ↓
Kafka Consumers (applications, Kafka UI)
        ↓
Downstream Systems (Analytics, Cache, Data Warehouse, etc.)
```

### Key Files & Components

| Component | Container | Port | Purpose |
|-----------|-----------|------|---------|
| PostgreSQL | cdc-postgres | 5438 | Source database with CDC enabled |
| Zookeeper | cdc-zookeeper | 2181 | Kafka coordination & metadata |
| Kafka | cdc-kafka | 29092 | Message broker & CDC event store |
| Debezium | cdc-debezium | 8083 | CDC connector & event processor |
| Kafka UI | cdc-kafka-ui | 8080 | Web monitoring interface |
| pgAdmin | cdc-pgadmin | 5050 | Database management GUI |

### Deployment Files

```
/Users/ajaydwivedi/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka/
├── playbook-deploy-all.yml          # Deploy full stack
├── roles/
│   ├── docker_infrastructure/        # Network & volumes
│   ├── kafka_ecosystem/              # Zookeeper, Kafka, Debezium, Kafka UI
│   ├── postgres_source/              # PostgreSQL with CDC
│   └── pgadmin/                      # Database management
├── vars/main.yml                     # Configuration (118 variables)
├── sensitive-values                  # Encrypted credentials
└── hosts.yml                         # Ansible inventory
```

### Starting Containers After a Host Reboot

Containers do **not** start automatically after a host reboot. Run these commands manually in order:

```bash
cd ~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka

# Step 1: Start Zookeeper first (Kafka depends on it)
docker start cdc-zookeeper
sleep 5

# Step 2: Start Kafka
docker start cdc-kafka
sleep 10

# Step 3: Start Debezium, Kafka UI, PostgreSQL, pgAdmin (order doesn't matter here)
docker start cdc-debezium cdc-kafka-ui cdc-postgres cdc-pgadmin

# Step 4: Wait ~15 seconds for Debezium to reconnect, then re-register the connector
sleep 15
PG_REPLICATION_PASSWORD=$(ansible-vault view sensitive-values --vault-password-file=vault-pass \
  | grep PG_REPLICATION_PASSWORD | awk '{print $2}' | tr -d '"')

curl -sf -X DELETE http://localhost:8083/connectors/postgres-cdc-connector 2>/dev/null || true
sleep 2
curl -X POST http://localhost:8083/connectors \
  -H 'Content-Type: application/json' \
  -d "{
    \"name\": \"postgres-cdc-connector\",
    \"config\": {
      \"connector.class\": \"io.debezium.connector.postgresql.PostgresConnector\",
      \"database.hostname\": \"cdc-postgres\",
      \"database.port\": \"5432\",
      \"database.user\": \"replication\",
      \"database.password\": \"${PG_REPLICATION_PASSWORD}\",
      \"database.dbname\": \"cdc_db\",
      \"database.server.name\": \"postgres-cdc\",
      \"topic.prefix\": \"postgres-cdc\",
      \"plugin.name\": \"pgoutput\",
      \"slot.name\": \"debezium_slot\",
      \"publication.name\": \"dbz_publication\",
      \"table.include.list\": \"public.users,public.orders,public.products\",
      \"snapshot.mode\": \"initial\"
    }
  }"

# Step 5: Verify everything is back up
docker ps --format "table {{.Names}}\t{{.Status}}"
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | python3 -m json.tool
```

> **Tip**: Alternatively, re-running the Ansible playbook achieves the same result:
> ```bash
> ansible-playbook -i hosts.yml playbook-deploy-all.yml --vault-password-file=vault-pass
> ```

---

### Quick Start Summary

```bash
# 1. Deploy everything (connector is registered automatically at the end)
cd ~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka
ansible-playbook -i hosts.yml playbook-deploy-all.yml --vault-password-file=vault-pass

# 2. Verify connector is RUNNING
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | python3 -m json.tool

# 3. Insert test data
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "INSERT INTO public.users (name, email) VALUES ('Test User', 'test@example.com');"

# 4. View CDC events in browser
open http://localhost:8080  # Kafka UI → Topics → postgres-cdc.public.users → Messages

# 5. View CDC events from CLI
docker exec cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic postgres-cdc.public.users \
  --from-beginning --max-messages 5

# 6. Live real-time demo (two terminals)
# Terminal 1 - watch:
docker exec cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic postgres-cdc.public.users

# Terminal 2 - trigger:
docker exec cdc-postgres psql -U postgres -d cdc_db \
  -c "INSERT INTO public.users (name, email) VALUES ('Live User', 'live@example.com');"
# → CDC event appears in Terminal 1 within ~1 second!
```

## Success Criteria

You've successfully set up Debezium CDC when:

✅ All 6 containers are running (`docker ps` shows `cdc-postgres`, `cdc-kafka`, `cdc-zookeeper`, `cdc-debezium`, `cdc-kafka-ui`, `cdc-pgadmin`)
✅ Debezium connector shows `"state":"RUNNING"` (`curl http://localhost:8083/connectors/postgres-cdc-connector/status`)
✅ Kafka topics exist: `postgres-cdc.public.users`, `postgres-cdc.public.orders`, `postgres-cdc.public.products`
✅ Message count in topics is > 0 after initial snapshot
✅ Inserting a row into PostgreSQL produces a new message in Kafka within ~1 second
✅ UPDATE shows `"op":"u"` with both `"before"` and `"after"` populated
✅ DELETE shows `"op":"d"` with `"before"` populated and `"after": null`
✅ No errors in Debezium logs (`docker logs cdc-debezium | grep ERROR`)

---

## CDC with Patroni HA Cluster (PostgreSQL 14+)

This section covers connecting Debezium to a **Patroni-managed PostgreSQL cluster** as the CDC
source — where the source is the Patroni HA cluster (pg1–pg3 primary, pg4 standby DR) rather
than a standalone PostgreSQL container.

The critical challenge: **logical replication slots do not automatically follow failovers**.
If pg1 (Leader) fails and pg2 is promoted, the `debezium_slot` that existed only on pg1 is gone
from pg2's perspective, and Debezium stalls. Patroni's `slots:` DCS feature solves this by
maintaining permanent logical slots synchronized across the entire cluster.

> **Reference**: [Patroni Docs — Permanent Replication Slots](https://patroni.readthedocs.io/en/latest/dynamic_configuration.html#:~:text=slots%3A%20define%20permanent%20replication%20slots)

---

### Requirements

| Requirement | Minimum | Why |
|---|---|---|
| PostgreSQL | **11+** | Logical slot files copied primary → replicas; PG 9.6/10 lack required functions |
| Patroni | **2.1.0+** | `slots:` DCS config and logical slot copy via libpq introduced |
| `wal_level` | `logical` | Must be set on all Patroni cluster nodes (requires rolling restart) |
| `use_slots` | `true` | Required for permanent slots to work (Patroni default on PG 9.4+) |
| `max_replication_slots` | ≥ 10 | Must have headroom for Debezium slot + member replication slots |
| `max_wal_senders` | ≥ 10 | Must allow connections from replicas + Debezium |

> Your lab cluster runs **PostgreSQL 18** with **Patroni 4.0.6** — all features are fully supported.

---

### Step 1: Set `wal_level = logical` on the Primary Cluster

`wal_level` must be `logical` (not `replica`) on all nodes so PostgreSQL can decode WAL for
Debezium. This requires a rolling restart. Add it under `postgresql.parameters:` in the DCS:

```bash
# Run from the Docker host — no interactive prompt
docker exec pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 --force \
  --set "postgresql.parameters.wal_level=logical" \
  --set "postgresql.parameters.wal_log_hints=on" \
  --set "postgresql.parameters.max_replication_slots=10" \
  --set "postgresql.parameters.max_wal_senders=10" \
  --set "postgresql.use_pg_rewind=true" \
  --set "postgresql.use_slots=true"
```

Expected DCS structure after the command (verify with `docker exec pg1 patronictl -c /etc/patroni/patroni.yml show-config`):

```yaml
postgresql:
  parameters:
    max_replication_slots: 10
    max_wal_senders: 10
    wal_level: logical          # ← must be logical, not replica
    wal_log_hints: 'on'
  use_pg_rewind: true
  use_slots: true
```

Then perform a rolling restart to apply the `wal_level` change:

```bash
# Rolling restart — replicas first, leader last (no downtime)
docker exec pg1 patronictl -c /etc/patroni/patroni.yml restart pg-docker-cls1 --force

# Verify after restart
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
docker exec pg1 psql -h 172.18.0.10 -U postgres -c "SHOW wal_level;"
# Expected: logical
```

---

### Step 2: Define Permanent Replication Slot in Patroni DCS

Add a `slots:` block to the primary cluster DCS config. Patroni will:

- Create `debezium_slot` on the Leader if it does not exist
- Copy it to all replicas (pg2, pg3) every `loop_wait` seconds via libpq
- Automatically re-create it on the new Leader after every failover
- Enable `hot_standby_feedback` on all replicas automatically (prevents vacuum from removing rows still needed for decoding)

```bash
# Run from the Docker host — no interactive prompt
docker exec pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 --force \
  --set "slots.debezium_slot.type=logical" \
  --set "slots.debezium_slot.database=cdc_db" \
  --set "slots.debezium_slot.plugin=pgoutput"
```

Expected DCS structure after the command (the `slots:` block appears at the root level, same indentation as `postgresql:`, `ttl:`, etc.):

```yaml
loop_wait: 10
master_start_timeout: 300
maximum_lag_on_failover: 1048576
postgresql:
  parameters:
    max_replication_slots: 10
    max_wal_senders: 10
    wal_level: logical
    wal_log_hints: 'on'
  use_pg_rewind: true
  use_slots: true
retry_timeout: 10
synchronous_mode: true
synchronous_mode_strict: false
synchronous_node_count: 1
ttl: 30
slots:                          # ← ADD THIS BLOCK
  debezium_slot:
    type: logical
    database: cdc_db               # ← replace with your CDC source database name
    plugin: pgoutput
```

> **Slot name**: Must exactly match the `slot.name` value in your Debezium connector config.
> **Database**: Replace `cdc_db` with the actual database you want to capture (e.g., `dba`).

Patroni applies the change within one `loop_wait` cycle (10 seconds). No restart needed.

---

### Step 3: Standby Cluster (pg4) — Slot Behaviour

The standby cluster (pg4, Standby Leader) has its **own separate DCS** (etcd running on pg4).
The primary cluster's DCS config does **not** apply to pg4.

| Scenario | What to do on pg4 |
|---|---|
| Debezium only reads from the primary cluster VIP | **No slots config needed on pg4.** Debezium reconnects to the primary cluster after failover within the primary DC (pg1→pg2). |
| pg4 is promoted (full DC failure) and becomes the new primary | Re-create the Debezium connector pointing to pg4. Patroni will create the slot on pg4 once you add `slots:` to its DCS. |

**If you need the slot pre-created on pg4 for faster DR recovery**, add the same `slots:` block
to pg4's DCS **only after pg4 is promoted**:

```bash
# Run from the Docker host — no interactive prompt (only after pg4 is promoted to primary)
docker exec pg4 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 --force \
  --set "slots.debezium_slot.type=logical" \
  --set "slots.debezium_slot.database=cdc_db" \
  --set "slots.debezium_slot.plugin=pgoutput"
```

**While pg4 is a Standby Leader** (streaming from the primary cluster), logical slots on pg4
are **not useful** — logical decoding can only run on the timeline-owning primary. Do not attempt
to consume from a logical slot on a Standby Leader.

---

### Step 4: Set Up Permissions on the Patroni Cluster

Connect via the Primary VIP and create the Debezium replication user and publication.
Because Patroni replicates all DDL and DML via WAL streaming, these objects will automatically
appear on pg2, pg3 (and pg4 via streaming replication) — no need to run on each node.

```sql
-- Connect via Patroni Primary VIP (172.18.0.10) or HAProxy write port (:5000)
-- psql -h 172.18.0.10 -U postgres -d <your_database>

-- 0. Connect to your database
\c cdc_db

-- 1. Create dedicated Debezium replication user
CREATE ROLE replication REPLICATION LOGIN PASSWORD 'your_password';

SELECT slot_name, plugin, slot_type, database, confirmed_flush_lsn FROM pg_replication_slots;

-- 2. Grant database and table access (for initial snapshot)
GRANT CONNECT ON DATABASE cdc_db TO replication;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO replication;

-- 3. Create publication (as superuser; slot is managed by Patroni via slots: config)
CREATE PUBLICATION dbz_publication FOR ALL TABLES;

-- 3.1. Create required table
CREATE TABLE replicate_me (id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY, name TEXT);

INSERT INTO replicate_me (name) VALUES ('PGConf.DE');

SELECT * FROM pg_logical_slot_peek_changes( 'debezium_slot', NULL, NULL); -- for test_decoding plugin

-- 4. Set REPLICA IDENTITY FULL on captured tables (required for UPDATE/DELETE events)
ALTER TABLE public.<table1> REPLICA IDENTITY FULL;
ALTER TABLE public.<table2> REPLICA IDENTITY FULL;

-- Do NOT manually create the replication slot — Patroni's slots: config manages it.
```

---

### Step 5: Allow Replication in pg_hba.conf (via Patroni DCS)

Add a `pg_hba:` entry for the Debezium host in the primary cluster DCS. Patroni regenerates
`pg_hba.conf` on all nodes and sends SIGHUP — no restart required.

The `pg_hba:` key holds a YAML list, which cannot be set with `--set` dot-notation.
Use the `--apply` flag with a JSON patch file instead, or append the entry directly to `pg_hba.conf`
on each node and reload — whichever matches how Patroni manages the file in your cluster.

**Option A — Append to pg_hba.conf on each node (works regardless of Patroni hba_file management):**

```bash
# Idempotently add the Debezium replication entry and reload on all primary cluster nodes
for node in pg1 pg2 pg3; do
  docker exec "$node" bash -c '
    HBA=$(psql -U postgres -tAc "SHOW hba_file;")
    grep -q "replication 172.18.0.0/16" "$HBA" || \
      echo "host  replication  replication 172.18.0.0/16 scram-sha-256" >> "$HBA"
    psql -U postgres -c "SELECT pg_reload_conf();"
  '
done
```

**Option B — Set the full `pg_hba:` list via Patroni DCS (only if Patroni manages pg_hba.conf):**

```bash
# Creates/replaces the entire pg_hba list in the DCS — Patroni regenerates pg_hba.conf and sends SIGHUP
docker exec pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 --force \
  --set 'postgresql.pg_hba=["local all postgres peer",
    "host all all 127.0.0.1/32 scram-sha-256",
    "host replication replicator 0.0.0.0/0 scram-sha-256",
    "host replication replication 172.18.0.0/16 scram-sha-256",
    "host all all 0.0.0.0/0 scram-sha-256",
    "host all all ::/0 scram-sha-256"]'
```

> **Note**: Option B replaces the entire `pg_hba` list in the DCS. Confirm the full list is correct
> before running — use `docker exec pg1 patronictl -c /etc/patroni/patroni.yml show-config` first.

---

### Step 6: Debezium Connector Configuration for Patroni Cluster

Connect Debezium via the **Keepalived Primary VIP** (`172.18.0.10`) so it automatically follows
the current Leader after every failover. Do **not** use a fixed node IP.

```bash
PG_REPLICATION_PASSWORD="your_password"

curl -sf -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"patroni-cdc-connector\",
    \"config\": {
      \"connector.class\": \"io.debezium.connector.postgresql.PostgresConnector\",
      \"database.hostname\": \"172.18.0.10\",
      \"database.port\": \"5432\",
      \"database.user\": \"replication\",
      \"database.password\": \"${PG_REPLICATION_PASSWORD}\",
      \"database.dbname\": \"dba\",
      \"topic.prefix\": \"patroni-cdc\",
      \"plugin.name\": \"pgoutput\",
      \"slot.name\": \"debezium_slot\",
      \"publication.name\": \"dbz_publication\",
      \"publication.autocreate.mode\": \"disabled\",
      \"slot.drop.on.stop\": \"false\",
      \"snapshot.mode\": \"initial\",
      \"heartbeat.interval.ms\": \"10000\"
    }
  }"
```

| Key Config | Value | Reason |
|---|---|---|
| `database.hostname` | `172.18.0.10` | Keepalived Primary VIP — always points to current Patroni Leader |
| `database.port` | `5432` | Direct PostgreSQL port inside the container |
| `slot.name` | `debezium_slot` | Must match the name in Patroni's `slots:` DCS config |
| `slot.drop.on.stop` | `false` | **Critical** — never drop the slot when connector stops; Patroni manages it |
| `publication.autocreate.mode` | `disabled` | Publication already created manually as superuser |
| `heartbeat.interval.ms` | `10000` | Keeps the slot LSN advancing even when no data changes occur |

> **Alternatively**, use the HAProxy write port (port `5000` inside each container, mapped to
> `15000/25000/35000` on the host) instead of the VIP. HAProxy health-checks Patroni's REST API
> (`GET /primary`) and only routes to the current primary, providing the same failover behaviour.

---

### Step 7: Verify Slot Replication Across All Nodes

After Patroni applies the `slots:` config, verify the slot exists on all nodes:

```bash
# Primary node (pg1 — current Leader)
psql -h 172.18.0.11 -U postgres -c \
  "SELECT slot_name, slot_type, plugin, database, active, confirmed_flush_lsn
   FROM pg_replication_slots WHERE slot_name = 'debezium_slot';"
# Expected: active=true (Debezium is connected), confirmed_flush_lsn advancing

# Sync Standby (pg2) — slot copied from primary, inactive
psql -h 172.18.0.12 -U postgres -c \
  "SELECT slot_name, slot_type, plugin, database, active, confirmed_flush_lsn
   FROM pg_replication_slots WHERE slot_name = 'debezium_slot';"
# Expected: active=false, confirmed_flush_lsn close to primary's value

# Replica (pg3) — same
psql -h 172.18.0.13 -U postgres -c \
  "SELECT slot_name, slot_type, plugin, database, active, confirmed_flush_lsn
   FROM pg_replication_slots WHERE slot_name = 'debezium_slot';"
```

Monitor slot lag across all nodes in one command:

```bash
for host in 172.18.0.11 172.18.0.12 172.18.0.13; do
  echo "=== $host ===";
  psql -h "$host" -U postgres -c \
    "SELECT slot_name, active, confirmed_flush_lsn, restart_lsn,
            pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) AS lag_bytes
     FROM pg_replication_slots WHERE slot_name = 'debezium_slot';" 2>/dev/null;
done
```

---

### Failover Behaviour — What Happens Step by Step

Scenario: pg1 (Leader) crashes; pg2 (Sync Standby) is promoted.

```
1. pg1 crashes
2. Patroni detects Leader loss (within loop_wait + retry_timeout = ~20 s)
3. pg2 is promoted to Leader (Keepalived VIP 172.18.0.10 moves to pg2)
4. debezium_slot already exists on pg2 (synchronized by Patroni's slots: config)
5. Debezium detects broken connection → reconnects to 172.18.0.10 (now pg2)
6. Debezium resumes reading from debezium_slot on pg2
7. Some messages committed just before the crash may be re-delivered (at-least-once)
8. pg3 continues streaming from pg2; slot is re-synchronized to pg3
```

To detect and discard duplicate messages in your consumer application:

```sql
-- Track the slot's confirmed_flush_lsn on the new primary
-- Your consumer should compare event LSN against the last committed LSN
SELECT slot_name, confirmed_flush_lsn
FROM pg_replication_slots
WHERE slot_name = 'debezium_slot';
```

---

### Key Warnings

> ⚠️ **Permanent slots are synchronized only from the Leader → replicas.**
> Debezium must connect only to the current Leader (via VIP or HAProxy). Connecting to a replica
> and consuming from the slot causes unbounded `pg_wal` growth on all other nodes in the cluster.

> ⚠️ **Never manually drop or re-create the replication slot** once it is under Patroni's `slots:`
> management. Use `patronictl edit-config` to remove it from the `slots:` block first, then drop
> it manually. Dropping a Patroni-managed slot manually causes Patroni to immediately re-create it.

> ⚠️ **`hot_standby_feedback` is enabled automatically** on all replicas when permanent logical
> slots are defined. This prevents VACUUM from removing rows that replicas still need for decoding
> but can cause table bloat on the primary if a replica falls far behind. Monitor replica lag.

> ⚠️ **`nostream` tag on a Patroni member** disables copying and synchronization of permanent
> logical slots on that node and all its cascading replicas. pg3 has `nosync: true` (not
> `nostream`), so slot synchronization to pg3 is not affected.

> ⚠️ **Logical slot failover on PostgreSQL < 11 is not supported.** For PostgreSQL 14+ (your
> environment), all features work correctly. PG 9.6 and 10 lack the internal functions required
> for slot file copying.

---

### Summary — Primary Cluster DCS Config (Final State)

```bash
docker exec pg1 patronictl -c /etc/patroni/patroni.yml show-config pg-docker-cls1
```

```yaml
loop_wait: 10
master_start_timeout: 300
maximum_lag_on_failover: 1048576
postgresql:
  parameters:
    max_replication_slots: 10
    max_wal_senders: 10
    wal_level: logical
    wal_log_hints: 'on'
  use_pg_rewind: true
  use_slots: true
  pg_hba:
    - local all postgres peer
    - host  all all      127.0.0.1/32   scram-sha-256
    - host  replication  replicator 0.0.0.0/0 scram-sha-256
    - host  replication  replication 172.18.0.0/16 scram-sha-256
    - host  all all      0.0.0.0/0      scram-sha-256
    - host  all all      ::/0           scram-sha-256
retry_timeout: 10
synchronous_mode: true
synchronous_mode_strict: false
synchronous_node_count: 1
ttl: 30
slots:
  debezium_slot:
    type: logical
    database: dba               # replace with your CDC source database
    plugin: pgoutput
```

---

**Last Updated**: 2026-05-12 (Added Patroni HA cluster CDC section, permissions setup, architecture diagram)
**Status**: Working CDC Learning Infrastructure
**Version**: 1.2 - Patroni HA cluster CDC support
