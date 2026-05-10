#!/bin/bash

# Quick status check of all CDC services

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Debezium CDC Infrastructure - Quick Status${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}\n"

# Docker containers
echo -e "${YELLOW}Running Containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "zk-cdc|kafka-cdc|postgres-cdc|debezium-connect|pgadmin4-cdc|kafka-ui-cdc" || echo "No CDC containers running"

echo ""
echo -e "${YELLOW}Access Endpoints:${NC}"
echo -e "  pgAdmin:          http://localhost:5050"
echo -e "  Kafka UI:         http://localhost:8080"
echo -e "  Debezium REST:    http://localhost:8083"
echo -e "  PostgreSQL CLI:   psql -h localhost -p 5433 -U postgres -d cdc_db"
echo -e "  pgBadger Portal:  http://localhost:8888 (after setup)"

echo ""
echo -e "${YELLOW}Service Status:${NC}"

# Zookeeper
if docker ps | grep -q "zk-cdc"; then
    echo -e "  Zookeeper:        ${GREEN}✓ Running${NC}"
else
    echo -e "  Zookeeper:        ${RED}✗ Stopped${NC}"
fi

# Kafka
if docker ps | grep -q "kafka-cdc"; then
    echo -e "  Kafka:            ${GREEN}✓ Running${NC}"
else
    echo -e "  Kafka:            ${RED}✗ Stopped${NC}"
fi

# PostgreSQL
if docker ps | grep -q "postgres-cdc"; then
    echo -e "  PostgreSQL:       ${GREEN}✓ Running${NC}"
else
    echo -e "  PostgreSQL:       ${RED}✗ Stopped${NC}"
fi

# Debezium
if docker ps | grep -q "debezium-connect"; then
    status=$(curl -s http://localhost:8083/connectors/postgres-cdc-connector/status 2>/dev/null | grep -o '"state":"[^"]*"' || echo "")
    if [[ $status == *"RUNNING"* ]]; then
        echo -e "  Debezium:         ${GREEN}✓ Running (Connector: RUNNING)${NC}"
    elif [[ $status == *"FAILED"* ]]; then
        echo -e "  Debezium:         ${RED}✗ Running (Connector: FAILED)${NC}"
    else
        echo -e "  Debezium:         ${GREEN}✓ Running (Connector: initializing)${NC}"
    fi
else
    echo -e "  Debezium:         ${RED}✗ Stopped${NC}"
fi

# pgAdmin
if docker ps | grep -q "pgadmin4-cdc"; then
    echo -e "  pgAdmin:          ${GREEN}✓ Running${NC}"
else
    echo -e "  pgAdmin:          ${RED}✗ Stopped${NC}"
fi

# Kafka UI
if docker ps | grep -q "kafka-ui-cdc"; then
    echo -e "  Kafka UI:         ${GREEN}✓ Running${NC}"
else
    echo -e "  Kafka UI:         ${RED}✗ Stopped${NC}"
fi

echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo -e "  Validate deployment:    ./scripts/validate-deployment.sh"
echo -e "  Test CDC flow:           ./scripts/test-cdc-flow.sh"
echo -e "  Full deployment:         ansible-playbook -i hosts.yml playbook-deploy-all.yml --vault-password-file=vault-pass"
echo -e "  Cleanup:                 ansible-playbook -i hosts.yml playbook-cleanup.yml --vault-password-file=vault-pass"
echo -e "  View container logs:     docker logs <container-name>"
echo -e "  List Kafka topics:       docker exec kafka-cdc kafka-topics.sh --list --bootstrap-server localhost:9092"

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}\n"
