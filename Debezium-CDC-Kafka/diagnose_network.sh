#!/bin/bash

echo "=== Docker Network & Container Diagnosis ==="
echo ""

echo "[1] Networks:"
docker network ls | grep cdc

echo ""
echo "[2] Containers on cdc-network:"
docker network inspect cdc-network 2>/dev/null | grep -A 50 "Containers" | head -20

echo ""
echo "[3] All running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}"

echo ""
echo "[4] Check Kafka service is accessible from Debezium container:"
docker exec tmp-debezium-connect-1 bash -c "nc -zv kafka 9092" 2>&1 || echo "Connection test completed"

echo ""
echo "[5] Check Zookeeper service is accessible:"
docker exec tmp-debezium-connect-1 bash -c "nc -zv zookeeper 2181" 2>&1 || echo "Connection test completed"

echo ""
echo "[6] Debezium environment variables:"
docker exec tmp-debezium-connect-1 env | grep -i kafka || echo "No KAFKA env vars"

echo ""
echo "[7] Check /tmp/kafka-ecosystem-compose.yml exists:"
ls -la /tmp/kafka-ecosystem-compose.yml 2>/dev/null || echo "File not found"

echo ""
echo "[8] Current docker-compose services:"
docker-compose -f /tmp/kafka-ecosystem-compose.yml ps 2>/dev/null || echo "docker-compose file not found"
