#!/bin/bash

# Read vault to get actual passwords
VAULT_DIR="/Users/ajaydwivedi/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka"
cd "$VAULT_DIR"

# Decrypt vault to get passwords
VAULT_CONTENT=$(ansible-vault view sensitive-values --vault-password-file=vault-pass 2>/dev/null)

# Extract passwords
PG_PASSWORD=$(echo "$VAULT_CONTENT" | grep "PG_SUPERUSER_PASSWORD" | awk '{print $2}' | tr -d '"')
PGADMIN_PASSWORD=$(echo "$VAULT_CONTENT" | grep "PGADMIN_DEFAULT_PASSWORD" | awk '{print $2}' | tr -d '"')

echo "=== Passwords from vault ==="
echo "PostgreSQL password: $PG_PASSWORD"
echo "pgAdmin password: $PGADMIN_PASSWORD"

# Test PostgreSQL connection
echo ""
echo "Testing PostgreSQL connection..."
export PGPASSWORD="$PG_PASSWORD"
psql -h localhost -p 5433 -U postgres -d cdc_db -c "SELECT 1;" 2>&1 && echo "✓ PostgreSQL connection successful" || echo "✗ PostgreSQL connection failed"

# Test pgAdmin (if running)
echo ""
echo "Testing pgAdmin access..."
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:5050 2>&1 || echo "✗ pgAdmin not accessible"

# Test Debezium REST API
echo ""
echo "Testing Debezium REST API..."
curl -s http://localhost:8083/connectors 2>&1 | head -5

echo ""
echo "Done."
