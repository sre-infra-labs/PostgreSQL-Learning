# Debezium PostgreSQL Connector Setup Guide

**Quick Navigation**: 
- PostgreSQL Setup (6 steps)
- Debezium Connector Creation (3 steps)
- Verification (2 steps)
- Testing Real-Time CDC (2 steps)

## Phase 1: PostgreSQL Setup (Prerequisites)

### Step 1: Verify PostgreSQL is Running
```bash
docker ps | grep postgres-cdc
# Should show: postgres-cdc ... Up
```

### Step 2: Verify Logical Replication is Enabled
```bash
docker exec postgres-cdc psql -U postgres -d cdc_db -c "SHOW wal_level;"
# Expected output: logical
```

### Step 3: Create Publication (What to Replicate)
```bash
docker exec postgres-cdc psql -U postgres -d cdc_db << 'EOF'
CREATE PUBLICATION dbz_publication FOR ALL TABLES;
SELECT * FROM pg_publication;
EOF
```

### Step 4: Create Replication Slot (Track What's Been Read)
```bash
docker exec postgres-cdc psql -U postgres -d cdc_db << 'EOF'
SELECT * FROM pg_create_logical_replication_slot('debezium_slot', 'pgoutput');
SELECT * FROM pg_replication_slots;
EOF
```

### Step 5: Set REPLICA IDENTITY FULL (Enable Full Row Capture)
```bash
docker exec postgres-cdc psql -U postgres -d cdc_db << 'EOF'
ALTER TABLE public.users REPLICA IDENTITY FULL;
ALTER TABLE public.orders REPLICA IDENTITY FULL;
ALTER TABLE public.products REPLICA IDENTITY FULL;
EOF
```

### Step 6: Verify Setup
```bash
docker exec postgres-cdc psql -U postgres -d cdc_db << 'EOF'
SELECT relname, pg_relation_replica_identity(oid) 
FROM pg_class WHERE relkind='r' AND relname IN ('users', 'orders', 'products');
EOF
# Expected: All show 'f' (FULL REPLICA IDENTITY)
```

## Phase 2: Debezium Connector Creation

### Step 1: Verify Debezium REST API is Running
```bash
curl -s http://localhost:8083/ | head -20
# Should return JSON with Debezium version

# Or check status
curl -s http://localhost:8083/connectors | jq .
# Should return: []
```

### Step 2: Create Connector Configuration File
```bash
cat > /tmp/debezium-postgres-connector.json << 'EOF'
{
  "name": "postgres-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres-cdc",
    "database.port": "5432",
    "database.user": "replication",
    "database.password": "YourStrongSuperUserPassword",
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
```

### Step 3: Create Connector (THE CRITICAL STEP!)
```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @/tmp/debezium-postgres-connector.json

# Expected response:
# {"name":"postgres-cdc-connector","config":{...},"tasks":[],"type":"source"}
```

## Phase 3: Verification

### Step 1: Check Connector Status
```bash
curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq .

# Expected output should show:
# "state": "RUNNING"
# No errors in "trace" field
```

### Step 2: Verify Kafka Topics Created
```bash
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092' | \
  grep postgres

# Expected topics:
# postgres.public.users
# postgres.public.orders
# postgres.public.products
```

## Phase 4: Test Real-Time CDC

### Test 1: View Historical Data (Initial Snapshot)
```bash
# Check how many messages from initial snapshot
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
    --broker-list localhost:9092 \
    --topic postgres.public.users'

# View messages with human-readable timestamps
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic postgres.public.users \
    --from-beginning \
    --property print.timestamp=true \
    --max-messages 5'
```

### Test 2: Real-Time CDC (Watch & Insert)
```bash
# TERMINAL 1: Start consumer (watches for NEW messages)
docker exec tmp-kafka-1 bash -c \
  '/opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic postgres.public.users \
    --property print.key=true'

# TERMINAL 2: Insert new data (you'll see it in Terminal 1 immediately!)
docker exec postgres-cdc psql -U postgres -d cdc_db \
  -c "INSERT INTO public.users (name, email) VALUES ('Real-Time User', 'realtime@example.com');"

# TERMINAL 1: You'll see output like:
# null  {"schema":{...},"payload":{"op":"c","ts_ms":1234567890,"after":{"id":5,"name":"Real-Time User","email":"realtime@example.com",...}}}
```

## Troubleshooting

### Connector Not Starting
```bash
# Check logs
docker logs tmp-debezium-connect-1 | grep -i error | head -20

# Common fixes:
# 1. Replication user doesn't exist
#    docker exec postgres-cdc psql -U postgres -d cdc_db \
#      -c "SELECT * FROM pg_user WHERE usename='replication';"
#
# 2. Publication not created
#    docker exec postgres-cdc psql -U postgres -d cdc_db \
#      -c "SELECT * FROM pg_publication;"
#
# 3. Replication slot not created
#    docker exec postgres-cdc psql -U postgres -d cdc_db \
#      -c "SELECT * FROM pg_replication_slots;"

# If needed, delete and recreate connector:
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-connector
# Then run Step 3 again
```

### No Messages in Kafka
```bash
# Check connector task status
curl -s http://localhost:8083/connectors/postgres-cdc-connector/tasks/0/status | jq .

# Check if in snapshot phase
docker logs tmp-debezium-connect-1 | grep -i snapshot | tail -5

# Force replication slot reset (if stuck)
docker exec postgres-cdc psql -U postgres -d cdc_db << 'EOF'
SELECT pg_drop_replication_slot('debezium_slot');
SELECT * FROM pg_create_logical_replication_slot('debezium_slot', 'pgoutput');
EOF

# Restart connector
curl -X POST http://localhost:8083/connectors/postgres-cdc-connector/restart
```

## Success Checklist

- ✅ PostgreSQL wal_level=logical
- ✅ Publication 'dbz_publication' created
- ✅ Replication slot 'debezium_slot' created
- ✅ REPLICA IDENTITY FULL on tables
- ✅ Debezium REST API responding
- ✅ Connector 'postgres-cdc-connector' RUNNING
- ✅ Kafka topics created
- ✅ Initial snapshot data in Kafka
- ✅ Real-time CDC working (inserts, updates, deletes appear in Kafka)
- ✅ Kafka UI showing messages flowing
