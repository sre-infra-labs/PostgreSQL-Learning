#!/bin/bash

# Validation script for Debezium CDC deployment
# Checks all services are running and healthy

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Debezium CDC Infrastructure - Deployment Validation${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}\n"

failed=0
passed=0

# Function to test a service
test_service() {
    local name=$1
    local container=$2
    local test_cmd=$3
    local check_port=$4
    
    echo -n "Testing $name ... "
    
    # Check if container exists and is running
    if ! docker ps | grep -q "$container"; then
        echo -e "${RED}✗ FAILED${NC} (container not running)"
        failed=$((failed + 1))
        return 1
    fi
    
    # Run test command if provided
    if [ -n "$test_cmd" ]; then
        if eval "$test_cmd" &>/dev/null; then
            echo -e "${GREEN}✓ PASSED${NC}"
            passed=$((passed + 1))
            return 0
        else
            echo -e "${RED}✗ FAILED${NC} (health check failed)"
            failed=$((failed + 1))
            return 1
        fi
    else
        echo -e "${GREEN}✓ RUNNING${NC}"
        passed=$((passed + 1))
        return 0
    fi
}

# Test Docker infrastructure
echo -e "${YELLOW}1. Docker Infrastructure${NC}"
test_service "Docker network (cdc-network)" "cdc-network" \
    "docker network ls | grep -q cdc-network"

# Test Zookeeper
echo -e "\n${YELLOW}2. Zookeeper${NC}"
test_service "Zookeeper" "zk-cdc" \
    "docker exec zk-cdc zkServer.sh status | grep -q 'Mode:'"

# Test Kafka
echo -e "\n${YELLOW}3. Kafka${NC}"
test_service "Kafka Broker" "kafka-cdc" \
    "docker exec kafka-cdc kafka-broker-api-versions.sh --bootstrap-server localhost:9092 | grep -q 'ApiVersion'"

# Test PostgreSQL
echo -e "\n${YELLOW}4. PostgreSQL${NC}"
test_service "PostgreSQL" "postgres-cdc" \
    "docker exec -e PGPASSWORD='ChangeMe_PostgresAdmin123!' postgres-cdc psql -U postgres -h localhost -c 'SELECT 1' 2>/dev/null"

# Test Debezium
echo -e "\n${YELLOW}5. Debezium${NC}"
test_service "Debezium Connect" "debezium-connect" \
    "curl -s http://localhost:8083/connectors 2>/dev/null | grep -q '\['"

test_service "Debezium Connector (postgres-cdc-connector)" "" \
    "curl -s http://localhost:8083/connectors | grep -q 'postgres-cdc-connector'"

# Test pgAdmin
echo -e "\n${YELLOW}6. pgAdmin${NC}"
test_service "pgAdmin 4" "pgadmin4-cdc" \
    "curl -s http://localhost:5050/misc/ping 2>/dev/null | grep -q 'SUCCESS'"

# Test Kafka UI
echo -e "\n${YELLOW}7. Kafka UI${NC}"
test_service "Kafka UI" "kafka-ui-cdc" \
    "curl -s http://localhost:8080/api/health 2>/dev/null | grep -q 'UP'"

# Test network connectivity
echo -e "\n${YELLOW}8. Network Connectivity${NC}"
echo -n "Testing inter-container connectivity (Kafka ↔ Zookeeper) ... "
if docker run --rm --network cdc-network busybox timeout 5 sh -c 'nc -zv kafka-cdc 9092 2>&1' &>/dev/null; then
    echo -e "${GREEN}✓ PASSED${NC}"
    passed=$((passed + 1))
else
    echo -e "${RED}✗ FAILED${NC}"
    failed=$((failed + 1))
fi

echo -n "Testing inter-container connectivity (Debezium ↔ PostgreSQL) ... "
if docker run --rm --network cdc-network busybox timeout 5 sh -c 'nc -zv postgres-cdc 5432 2>&1' &>/dev/null; then
    echo -e "${GREEN}✓ PASSED${NC}"
    passed=$((passed + 1))
else
    echo -e "${RED}✗ FAILED${NC}"
    failed=$((failed + 1))
fi

# Test Kafka topics
echo -e "\n${YELLOW}9. Kafka Topics${NC}"
echo -n "Checking Kafka topics ... "
if docker exec kafka-cdc kafka-topics.sh --list --bootstrap-server localhost:9092 2>/dev/null | grep -q "postgres.public"; then
    echo -e "${GREEN}✓ PASSED${NC} (topics exist)"
    passed=$((passed + 1))
else
    echo -e "${RED}✗ FAILED${NC} (topics not found)"
    failed=$((failed + 1))
fi

# Test PostgreSQL replication
echo -e "\n${YELLOW}10. PostgreSQL Replication${NC}"
echo -n "Checking PostgreSQL WAL level (wal_level=logical) ... "
if docker exec -e PGPASSWORD='ChangeMe_PostgresAdmin123!' postgres-cdc \
    psql -U postgres -h localhost -t -c "SHOW wal_level" 2>/dev/null | grep -q "logical"; then
    echo -e "${GREEN}✓ PASSED${NC}"
    passed=$((passed + 1))
else
    echo -e "${RED}✗ FAILED${NC}"
    failed=$((failed + 1))
fi

echo -n "Checking replication user exists ... "
if docker exec -e PGPASSWORD='ChangeMe_Replication456!' postgres-cdc \
    psql -U replication -h localhost -d cdc_db -c "SELECT 1" 2>/dev/null; then
    echo -e "${GREEN}✓ PASSED${NC}"
    passed=$((passed + 1))
else
    echo -e "${RED}✗ FAILED${NC}"
    failed=$((failed + 1))
fi

# Display summary
echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "Validation Summary: ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}\n"

# Exit with appropriate code
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✓ All validations PASSED - Infrastructure is healthy!${NC}\n"
    exit 0
else
    echo -e "${RED}✗ Some validations FAILED - Check logs above${NC}\n"
    exit 1
fi
