#!/bin/bash

# Test CDC Flow - Insert data in PostgreSQL and consume from Kafka
# This script demonstrates end-to-end CDC flow

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PG_PASSWORD="ChangeMe_PostgresAdmin123!"
PG_HOST="localhost"
PG_PORT="5433"
PG_DB="cdc_db"
PG_USER="postgres"

echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Debezium CDC Flow Test${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}\n"

# Function to execute PostgreSQL command
execute_sql() {
    PGPASSWORD=$PG_PASSWORD psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DB -c "$1"
}

# Step 1: Check PostgreSQL connectivity
echo -e "${BLUE}Step 1: Checking PostgreSQL connectivity...${NC}"
if execute_sql "SELECT 'PostgreSQL Connected' as status;" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Connected to PostgreSQL${NC}\n"
else
    echo -e "${RED}✗ Failed to connect to PostgreSQL${NC}"
    exit 1
fi

# Step 2: Check Debezium connector status
echo -e "${BLUE}Step 2: Checking Debezium connector status...${NC}"
connector_status=$(curl -s http://localhost:8083/connectors/postgres-cdc-connector/status 2>/dev/null | grep '"state"' | head -1 || echo "")
if [[ $connector_status == *"RUNNING"* ]]; then
    echo -e "${GREEN}✓ Debezium connector is RUNNING${NC}\n"
else
    echo -e "${RED}✗ Debezium connector is not running or not found${NC}"
    echo -e "${YELLOW}Try deploying Debezium: ansible-playbook -i hosts.yml playbook-deploy-all.yml --vault-password-file=vault-pass --tags debezium${NC}"
    exit 1
fi

# Step 3: Clear test tables (optional)
echo -e "${BLUE}Step 3: Preparing test data...${NC}"
execute_sql "DELETE FROM public.users;" >/dev/null 2>&1
execute_sql "DELETE FROM public.orders;" >/dev/null 2>&1
echo -e "${GREEN}✓ Cleared previous test data${NC}\n"

# Step 4: Insert test data
echo -e "${BLUE}Step 4: Inserting test data into PostgreSQL...${NC}"
echo "Inserting user: John Doe (john@example.com)"
execute_sql "INSERT INTO public.users (name, email) VALUES ('John Doe', 'john@example.com');" >/dev/null
sleep 1

echo "Inserting user: Jane Smith (jane@example.com)"
execute_sql "INSERT INTO public.users (name, email) VALUES ('Jane Smith', 'jane@example.com');" >/dev/null
sleep 1

echo "Inserting order for user 1"
execute_sql "INSERT INTO public.orders (user_id, amount) VALUES (1, 99.99);" >/dev/null
sleep 1

echo "Inserting order for user 2"
execute_sql "INSERT INTO public.orders (user_id, amount) VALUES (2, 149.99);" >/dev/null
sleep 2

echo -e "${GREEN}✓ Test data inserted${NC}\n"

# Step 5: Display inserted data
echo -e "${BLUE}Step 5: Verifying data in PostgreSQL...${NC}"
echo "Users:"
execute_sql "SELECT id, name, email FROM public.users ORDER BY id;" 
echo ""
echo "Orders:"
execute_sql "SELECT id, user_id, amount FROM public.orders ORDER BY id;" 
echo ""

# Step 6: Check Kafka topics
echo -e "${BLUE}Step 6: Checking Kafka topics for messages...${NC}"
echo -e "${YELLOW}Note: Consuming last 5 messages from postgres.public.users topic...${NC}"
echo "(This will timeout after 5 seconds - that's normal)"
echo ""

timeout 5 docker exec kafka-cdc \
    kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic postgres.public.users \
    --from-beginning \
    --max-messages 5 2>/dev/null || true

echo ""
echo -e "${GREEN}✓ Messages from Kafka topic (if any shown above)${NC}\n"

# Step 7: Summary
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ CDC Flow Test Completed${NC}\n"

echo -e "To continuously monitor Kafka messages (in separate terminal):\n"
echo -e "${BLUE}docker exec kafka-cdc kafka-console-consumer.sh \\${NC}"
echo -e "${BLUE}  --bootstrap-server localhost:9092 \\${NC}"
echo -e "${BLUE}  --topic postgres.public.users \\${NC}"
echo -e "${BLUE}  --from-beginning${NC}\n"

echo -e "To insert more data (in another terminal):\n"
echo -e "${BLUE}psql -h localhost -p 5433 -U postgres -d cdc_db${NC}"
echo -e "${BLUE}INSERT INTO public.users (name, email) VALUES ('Your Name', 'your@email.com');${NC}\n"

echo -e "To view in Kafka UI:\n"
echo -e "${BLUE}http://localhost:8080${NC}\n"

echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}\n"
