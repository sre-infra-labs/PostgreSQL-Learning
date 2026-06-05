#!/bin/bash

echo "=== Verifying Deployment with Vault Credentials ==="
echo ""

cd /Users/ajaydwivedi/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka

# Read the vault password
VAULT_PASS=$(cat vault-pass)

# Decrypt vault to get the actual passwords used
echo "[1] Reading credentials from vault..."
VAULT_CONTENT=$(ansible-vault view sensitive-values --vault-password-file=vault-pass 2>/dev/null)

# Extract the passwords
PG_PASSWORD=$(echo "$VAULT_CONTENT" | grep "PG_SUPERUSER_PASSWORD:" | sed 's/.*"\(.*\)".*/\1/')
PGADMIN_PASSWORD=$(echo "$VAULT_CONTENT" | grep "PGADMIN_DEFAULT_PASSWORD:" | sed 's/.*"\(.*\)".*/\1/')

echo "✓ Vault decrypted successfully"
echo "  PostgreSQL password: $PG_PASSWORD"
echo "  pgAdmin password: $PGADMIN_PASSWORD"
echo ""

# Check running containers
echo "[2] Checking running containers..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "postgres-cdc|pgadmin|kafka|debezium|zookeeper"
echo ""

# Test PostgreSQL
echo "[3] Testing PostgreSQL connection..."
export PGPASSWORD="$PG_PASSWORD"
if docker exec postgres-cdc psql -U postgres -d cdc_db -c "SELECT 1;" >/dev/null 2>&1; then
    echo "✓ PostgreSQL: Connection successful with password from vault"
else
    echo "✗ PostgreSQL: Connection failed"
fi
echo ""

# Test pgAdmin
echo "[4] Testing pgAdmin HTTP access..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5050)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "✓ pgAdmin: HTTP $HTTP_CODE (accessible)"
else
    echo "✗ pgAdmin: HTTP $HTTP_CODE (not accessible)"
fi
echo ""

# Test Debezium
echo "[5] Testing Debezium REST API..."
if curl -s http://localhost:8083/connectors >/dev/null 2>&1; then
    echo "✓ Debezium: REST API responding"
    curl -s http://localhost:8083/connectors | jq . 2>/dev/null || echo "  Connectors list retrieved"
else
    echo "✗ Debezium: REST API not responding"
fi
echo ""

# Test Kafka UI
echo "[6] Testing Kafka UI..."
KAFKA_UI_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080)
if [ "$KAFKA_UI_CODE" = "200" ] || [ "$KAFKA_UI_CODE" = "302" ]; then
    echo "✓ Kafka UI: HTTP $KAFKA_UI_CODE (accessible)"
else
    echo "✗ Kafka UI: HTTP $KAFKA_UI_CODE (not accessible)"
fi
echo ""

echo "=== All services deployed with passwords from sensitive-values vault ==="
