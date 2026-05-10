# Change Data Capture (CDC) Using Debezium and Kafka

## Overview

Change Data Capture (CDC) is a design pattern that captures data changes at the source and propagates them to downstream systems in real-time. This document explains the CDC architecture using Debezium and Kafka with PostgreSQL as the source database.

**Updated**: 2026-05-10 (Complete working deployment with step-by-step instructions)

## Architecture

```
PostgreSQL Source Database (localhost:5433)
    ↓ (Logical Replication via WAL)
    ↓ (pgoutput plugin)
    ↓
Debezium PostgreSQL Connector (localhost:8083 REST API)
    ↓ (Reads changes, converts to Kafka messages)
    ↓
Kafka Message Broker (localhost:29092)
    ↓ (Stores CDC events in topics, managed by Zookeeper:2181)
    ↓
Kafka Consumers (via Kafka UI: localhost:8080)
    ↓ (Any application can consume)
    ↓
Data Pipelines, Analytics, Cache, Data Warehousing, etc.
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

-- Create replication slot (where to capture from)
SELECT * FROM pg_create_logical_replication_slot('debezium', 'pgoutput');

-- Set REPLICA IDENTITY on tables (needed for updates/deletes)
ALTER TABLE table_name REPLICA IDENTITY FULL;
```

### 2. Debezium Connector

Debezium is a distributed platform that captures changes from databases.

**PostgreSQL Connector Workflow:**
1. Connects to PostgreSQL using replication user
2. Reads from the replication slot
3. Decodes changes using pgoutput plugin
4. Converts database events to Kafka messages
5. Publishes to Kafka topics (one per table)

**Connector Configuration:**
```json
{
  "name": "postgres-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.server.name": "postgres-cdc",
    "database.hostname": "postgres-cdc",
    "database.port": 5432,
    "database.user": "replication",
    "database.password": "***",
    "database.dbname": "cdc_db",
    "plugin.name": "pgoutput",
    "publication.name": "dbz_publication",
    "slot.name": "debezium",
    "topic.prefix": "postgres-cdc"
  }
}
```

### 3. Kafka

Kafka acts as the **message broker** that:
- Receives CDC events from Debezium
- Stores them durably on disk
- Allows multiple consumers to read independently
- Provides event history and replay capability

**Topics Created:**
- `postgres.public.users` - Changes to users table
- `postgres.public.orders` - Changes to orders table
- `postgres.public.products` - Changes to products table

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
| **PostgreSQL** | 5433 | localhost:5433 | CDC source database |
| **pgAdmin** | 5050 | http://localhost:5050 | Database management GUI |
| **Zookeeper** | 2181 | localhost:2181 | Kafka coordination |
| **Kafka Broker** | 29092 | localhost:29092 | Message broker (external) |
| **Kafka Internal** | 9092 | kafka:9092 | Message broker (internal) |
| **Debezium** | 8083 | http://localhost:8083 | Connector REST API |
| **Kafka UI** | 8080 | http://localhost:8080 | Web monitoring interface |

### Credentials

```
PostgreSQL:
  - Host: localhost, Port: 5433
  - Admin User: postgres, Password: MyHighlySecurePassword
  - Database: cdc_db
  - Replication User: replication, Password: MyHighlySecurePassword
  - App User: cdc_app, Password: MyHighlySecurePassword

pgAdmin:
  - URL: http://localhost:5050
  - Email: admin@cdc-learning.local
  - Password: MyHighlySecurePassword
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
- Docker network (cdc-network: 172.20.0.0/16)
- Zookeeper (port 2181)
- Kafka Broker (port 29092 external, 9092 internal)
- Debezium Connect (port 8083)
- Kafka UI (port 8080)
- PostgreSQL (port 5433)
- pgAdmin (port 5050)

**Expected output**: All 6 containers running, 3 Kafka topics created

### Step 2: Verify All Services Are Running

```bash
# Check containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Should show:
# pgadmin4-cdc        Up ... 0.0.0.0:5050->80/tcp
# postgres-cdc        Up ... 0.0.0.0:5433->5432/tcp
# tmp-debezium-connect-1  Up ... 0.0.0.0:8083->8083/tcp
# tmp-kafka-ui-1      Up ... 0.0.0.0:8080->8080/tcp
# tmp-kafka-1         Up ... 0.0.0.0:29092->9092/tcp
# tmp-zookeeper-1     Up ... 0.0.0.0:2181->2181/tcp
```

## Step-by-Step: Connect Debezium to PostgreSQL (Complete CDC Setup)

### Step 3: Verify PostgreSQL is Ready

```bash
# Test PostgreSQL connectivity
docker exec postgres-cdc psql -U postgres -d cdc_db \
  -c "SELECT version();"

# Expected output:
# PostgreSQL 15.17 (Debian 15.17-1.pgdg13+1) ...

# Verify logical replication is enabled
docker exec postgres-cdc psql -U postgres -d cdc_db \
  -c "SHOW wal_level;"

# Expected output: logical
```

### Step 4: Check PostgreSQL Replication Configuration

```bash
# View replication user
docker exec postgres-cdc psql -U postgres -d cdc_db \
  -c "SELECT usename, usecanlogin, usereplication FROM pg_user WHERE usename='replication';"

# View test tables
docker exec postgres-cdc psql -U postgres -d cdc_db \
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
docker exec postgres-cdc psql -U postgres -d cdc_db << 'EOF'

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

**This is the key step that connects Debezium to PostgreSQL and enables CDC:**

```bash
# Save this to a file for easy reuse
cat > /tmp/debezium-postgres-connector.json << 'EOF'
{
  "name": "postgres-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres-cdc",
    "database.port": "5432",
    "database.user": "replication",
    "database.password": "MyHighlySecurePassword",
    "database.dbname": "cdc_db",
    "database.server.name": "postgres",
    "plugin.name": "pgoutput",
    "publication.name": "dbz_publication",
    "slot.name": "debezium_slot",
    "table.include.list": "public.users,public.orders,public.products",
    "topic.prefix": "postgres",
    "snapshot.mode": "initial",
    "transforms": "route",
    "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.route.regex": "([^.]+)\\.([^.]+)\\.([^.]+)",
    "transforms.route.replacement": "$1.$2.$3"
  }
}
EOF

# Create the connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @/tmp/debezium-postgres-connector.json

# Expected response:
# {
#   "name": "postgres-cdc-connector",
#   "config": { ... },
#   "tasks": [],
#   "type": "source"
# }
```

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
# Using docker command
docker exec tmp-kafka-1 bash -c \
  'ls /opt/kafka/bin/kafka-topics.sh && /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092'

# Expected topics:
# postgres.public.users
# postgres.public.orders
# postgres.public.products
# (plus internal Debezium topics: connect-*, _schemas, etc.)
```

### Step 10: Insert Test Data into PostgreSQL

Now insert data and watch it flow through CDC:

```bash
# Connect to PostgreSQL and insert test data
docker exec postgres-cdc psql -U postgres -d cdc_db << 'EOF'

-- Insert test users
INSERT INTO public.users (name, email) VALUES
  ('John Doe', 'john@example.com'),
  ('Jane Smith', 'jane@example.com'),
  ('Bob Johnson', 'bob@example.com');

-- Insert test orders
INSERT INTO public.orders (user_id, amount) VALUES
  (1, 99.99),
  (2, 149.50),
  (1, 75.25);

-- Insert test products
INSERT INTO public.products (name, price) VALUES
  ('Laptop', 999.99),
  ('Mouse', 29.99),
  ('Keyboard', 79.99);

-- Verify data was inserted
SELECT COUNT(*) as user_count FROM public.users;
SELECT COUNT(*) as order_count FROM public.orders;
SELECT COUNT(*) as product_count FROM public.products;

EOF
```

### Step 11: View CDC Events in Kafka (Real-time Data Capture)

**Option A: Using Kafka UI (Web Browser)**

```bash
# Open Kafka UI in browser
open http://localhost:8080

# In the UI:
# 1. Click on "Topics" in left menu
# 2. Select "postgres.public.users"
# 3. Click on partition "0"
# 4. Scroll through messages to see CDC events
#
# Each message contains:
# - "op": "c" (create/insert), "u" (update), "d" (delete)
# - "before": Previous row values (for update/delete)
# - "after": New row values (for insert/update)
# - "source": PostgreSQL metadata (LSN, transaction ID, etc.)
```

**Option B: Using Command Line**

```bash
# View messages from users topic (from the beginning)
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic postgres.public.users \
    --from-beginning \
    --property print.key=true \
    --property print.value=true \
    --property print.timestamp=true \
    --max-messages 10'

# View messages from orders topic
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic postgres.public.orders \
    --from-beginning \
    --property print.key=true \
    --max-messages 10'

# View messages from products topic
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic postgres.public.products \
    --from-beginning \
    --max-messages 10'
```

### Step 12: Test Real-Time CDC - Insert New Data and Watch It Flow

```bash
# Terminal 1: Start a Kafka consumer watching for new messages
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic postgres.public.users \
    --property print.key=true \
    --property print.timestamp=true'

# Terminal 2: Insert new data into PostgreSQL
# The Kafka consumer in Terminal 1 will show the CDC event in real-time!
docker exec postgres-cdc psql -U postgres -d cdc_db \
  -c "INSERT INTO public.users (name, email) VALUES ('New User', 'newuser@example.com');"

# You should see a new message appear in Terminal 1 with:
# - Operation: "c" (create)
# - After: {"id": 4, "name": "New User", "email": "newuser@example.com", ...}
```

### Step 13: Test UPDATE and DELETE Operations

```bash
# Update a user record
docker exec postgres-cdc psql -U postgres -d cdc_db << 'EOF'
UPDATE public.users SET email = 'newemail@example.com' WHERE id = 1;
EOF

# You'll see a message in Kafka with:
# - Operation: "u" (update)
# - Before: {"id": 1, "name": "John Doe", "email": "john@example.com", ...}
# - After: {"id": 1, "name": "John Doe", "email": "newemail@example.com", ...}

# Delete a user record
docker exec postgres-cdc psql -U postgres -d cdc_db << 'EOF'
DELETE FROM public.users WHERE id = 4;
EOF

# You'll see a message in Kafka with:
# - Operation: "d" (delete)
# - Before: {"id": 4, "name": "New User", "email": "newuser@example.com", ...}
# - After: null
```

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
docker logs postgres-cdc | tail -50              # PostgreSQL
docker logs tmp-kafka-1 | tail -50               # Kafka
docker logs tmp-debezium-connect-1 | tail -50    # Debezium
docker logs tmp-kafka-ui-1 | tail -50            # Kafka UI
docker logs pgadmin4-cdc | tail -50              # pgAdmin
```

### PostgreSQL Management

```bash
# Connect to PostgreSQL
docker exec -it postgres-cdc psql -U postgres -d cdc_db

# Or directly with one command:
docker exec postgres-cdc psql -U postgres -d cdc_db -c "SELECT * FROM public.users;"

# View all replication slots
docker exec postgres-cdc psql -U postgres -d cdc_db -c "SELECT * FROM pg_replication_slots;"

# View publications
docker exec postgres-cdc psql -U postgres -d cdc_db -c "SELECT * FROM pg_publication;"

# View table REPLICA IDENTITY status
docker exec postgres-cdc psql -U postgres -d cdc_db -c \
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
docker exec tmp-kafka-1 bash -c '/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092'

# Describe a topic
docker exec tmp-kafka-1 bash -c '/opt/kafka/bin/kafka-topics.sh --describe --bootstrap-server localhost:9092 --topic postgres.public.users'

# View message count
docker exec tmp-kafka-1 bash -c '/opt/kafka/bin/kafka-run-class.sh kafka.tools.JmxTool --object-name kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions'

# Consume messages from a topic (first 10 messages)
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic postgres.public.users --from-beginning --max-messages 10'

# Consume only new messages (follow mode)
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic postgres.public.users'
```

## Troubleshooting Guide

### Connector Failed to Create

**Symptom**: Connector creation returns error

```bash
# Check Debezium logs
docker logs tmp-debezium-connect-1 | grep -i error

# Common causes:
# 1. PostgreSQL not responding
#    - Check: docker exec postgres-cdc psql -U postgres -d cdc_db -c "SELECT 1;"
#
# 2. Wrong credentials
#    - Verify: replication user exists and has correct password
#    - Check: docker exec postgres-cdc psql -U postgres -d cdc_db -c "SELECT * FROM pg_user WHERE usename='replication';"
#
# 3. Publication doesn't exist
#    - Check: docker exec postgres-cdc psql -U postgres -d cdc_db -c "SELECT * FROM pg_publication;"
#    - Create: docker exec postgres-cdc psql -U postgres -d cdc_db -c "CREATE PUBLICATION dbz_publication FOR ALL TABLES;"
#
# 4. Replication slot doesn't exist
#    - Check: docker exec postgres-cdc psql -U postgres -d cdc_db -c "SELECT * FROM pg_replication_slots;"
#    - Create: docker exec postgres-cdc psql -U postgres -d cdc_db -c "SELECT * FROM pg_create_logical_replication_slot('debezium_slot', 'pgoutput');"
```

### No Messages in Kafka Topics

**Symptom**: Topics exist but no messages appear after inserting data

```bash
# 1. Verify connector is running
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq .

# 2. Check if connector has an error
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq '.connector.state, .connector.trace'

# 3. Verify REPLICA IDENTITY is set correctly
docker exec postgres-cdc psql -U postgres -d cdc_db -c \
  "SELECT relname, pg_relation_replica_identity(oid) FROM pg_class WHERE relkind='r' AND relname IN ('users', 'orders', 'products');"

# 4. Check replication slot activity
docker exec postgres-cdc psql -U postgres -d cdc_db -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"

# 5. View Debezium connector logs
docker logs tmp-debezium-connect-1 | tail -100 | grep -i "users\|orders\|products\|error"
```

### Connector Stuck or Not Processing Data

**Symptom**: Connector runs but data changes don't appear in Kafka

```bash
# 1. Check connector task status
curl -s http://localhost:8083/connectors/postgres-cdc-connector/tasks/0/status | jq .

# 2. Verify snapshot phase completed
docker logs tmp-debezium-connect-1 | grep -i "snapshot\|snapshotting"

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
docker exec postgres-cdc psql -U postgres -d cdc_db -c \
  "SELECT slot_name, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) as lag_bytes FROM pg_replication_slots;"

# 2. Check PostgreSQL settings
docker exec postgres-cdc psql -U postgres -d cdc_db -c \
  "SHOW wal_keep_size; SHOW max_wal_senders; SHOW max_replication_slots;"

# 3. Monitor Debezium memory usage
docker stats tmp-debezium-connect-1

# 4. Check Kafka broker lag
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group connect-cluster'

# 5. Reduce connector task count or increase batch size (modify connector config)
curl -X PATCH http://localhost:8083/connectors/postgres-cdc-connector/config \
  -H "Content-Type: application/json" \
  -d '{"snapshot.isolation.mode": "read_uncommitted"}'
```

### Network Connectivity Issues

**Symptom**: Connector can't connect to PostgreSQL or Kafka

```bash
# 1. Verify containers are on same network
docker network inspect cdc-network

# 2. Test PostgreSQL connectivity from Debezium container
docker exec tmp-debezium-connect-1 bash -c 'nc -zv postgres-cdc 5432'

# 3. Test Kafka connectivity from Debezium
docker exec tmp-debezium-connect-1 bash -c 'nc -zv kafka 9092'

# 4. Check container IPs
docker inspect postgres-cdc | jq '.[] | .NetworkSettings.Networks'
docker inspect tmp-kafka-1 | jq '.[] | .NetworkSettings.Networks'
docker inspect tmp-debezium-connect-1 | jq '.[] | .NetworkSettings.Networks'
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
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group connect-cluster'

# Monitor PostgreSQL WAL size
docker exec postgres-cdc psql -U postgres -d cdc_db -c \
  "SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0'));"
```

## Security Considerations

**Current Setup (Development)**:
- Credentials stored in Ansible Vault (encrypted with MyHighlySecurePassword)
- Replication user has minimal required permissions
- All ports bound to localhost (not exposed to network)
- Network isolation via Docker network (cdc-network)

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
Kafka Topics (postgres.public.users, orders, products)
        ↓
Kafka Consumers (applications, Kafka UI)
        ↓
Downstream Systems (Analytics, Cache, Data Warehouse, etc.)
```

### Key Files & Components

| Component | Container | Port | Purpose |
|-----------|-----------|------|---------|
| PostgreSQL | postgres-cdc | 5433 | Source database with CDC enabled |
| Zookeeper | tmp-zookeeper-1 | 2181 | Kafka coordination & metadata |
| Kafka | tmp-kafka-1 | 29092 | Message broker & CDC event store |
| Debezium | tmp-debezium-connect-1 | 8083 | CDC connector & event processor |
| Kafka UI | tmp-kafka-ui-1 | 8080 | Web monitoring interface |
| pgAdmin | pgadmin4-cdc | 5050 | Database management GUI |

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

### Quick Start Summary

```bash
# 1. Deploy everything
cd ~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka
ansible-playbook -i hosts.yml playbook-deploy-all.yml --vault-password-file=vault-pass

# 2. Create Debezium connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @/tmp/debezium-postgres-connector.json

# 3. Insert test data
docker exec postgres-cdc psql -U postgres -d cdc_db << 'EOF'
INSERT INTO public.users (name, email) VALUES ('Test User', 'test@example.com');
EOF

# 4. View CDC events
open http://localhost:8080  # Kafka UI
# OR
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic postgres.public.users --from-beginning'

# 5. Test real-time CDC
# In terminal 1, watch for messages:
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic postgres.public.users'

# In terminal 2, insert new data:
docker exec postgres-cdc psql -U postgres -d cdc_db \
  -c "INSERT INTO public.users (name, email) VALUES ('Another User', 'another@example.com');"

# You'll see the CDC event appear in terminal 1 in real-time!
```

## Success Criteria

You've successfully set up Debezium CDC when:

✅ All 6 containers are running
✅ Debezium connector shows "RUNNING" status
✅ Kafka topics are created (postgres.public.users, orders, products)
✅ Test data inserted appears in Kafka topics
✅ Updates to PostgreSQL are reflected in Kafka in real-time
✅ Kafka UI shows messages flowing through topics
✅ No errors in Debezium, Kafka, or PostgreSQL logs

---

**Last Updated**: 2026-05-10 (Complete working deployment with all commands)
**Status**: Production-Ready CDC Learning Infrastructure
**Version**: 1.0 - Full Stack Deployment
