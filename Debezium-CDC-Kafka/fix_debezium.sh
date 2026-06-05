#!/bin/bash

echo "=== Fixing Debezium Kafka Connection ==="
echo ""

# Check if Kafka container is running
echo "[1] Checking Kafka status..."
if docker ps | grep -q "kafka" | grep -v debezium; then
    echo "✓ Kafka container found"
    KAFKA_CONTAINER=$(docker ps --format "{{.Names}}" | grep "^kafka$\|kafka-1\|kafka_kafka" | head -1)
    echo "  Kafka container: $KAFKA_CONTAINER"
else
    echo "✗ No Kafka container found"
    docker ps --format "table {{.Names}}\t{{.Image}}"
    exit 1
fi

# Check Kafka logs
echo ""
echo "[2] Kafka container logs (last 20 lines):"
docker logs --tail 20 $KAFKA_CONTAINER 2>&1 | tail -15

# Check if Kafka is healthy
echo ""
echo "[3] Testing Kafka broker health..."
docker exec $KAFKA_CONTAINER bash -c "kafka-broker-api-versions.sh --bootstrap-server localhost:9092" 2>&1 | head -5

# Check Debezium container
echo ""
echo "[4] Debezium container status:"
DEBEZIUM_CONTAINER="tmp-debezium-connect-1"
docker ps | grep $DEBEZIUM_CONTAINER || echo "Container $DEBEZIUM_CONTAINER not found"

# Restart Debezium to reconnect
echo ""
echo "[5] Restarting Debezium container..."
docker restart $DEBEZIUM_CONTAINER

# Wait for restart
sleep 10

# Check logs after restart
echo ""
echo "[6] Debezium logs after restart:"
docker logs --tail 30 $DEBEZIUM_CONTAINER 2>&1 | tail -20

echo ""
echo "=== Fix completed ==="
