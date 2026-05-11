#!/bin/bash

cd /Users/ajaydwivedi/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka

echo "================================"
echo "Deploying with vault credentials"
echo "================================"

# Stop and remove old containers (optional - comment out if you want to keep data)
# docker rm -f postgres-cdc pgadmin4-cdc kafka-ecosystem-cdc 2>/dev/null

# Run deployment with vault password
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  -v

echo ""
echo "================================"
echo "Deployment complete"
echo "================================"
echo ""
echo "Verifying deployed services..."
echo ""

# Wait for services to start
sleep 5

# Check PostgreSQL
echo "✓ PostgreSQL:"
docker exec postgres-cdc psql -U postgres -d cdc_db -c "SELECT 1;" >/dev/null 2>&1 && echo "  Connection OK" || echo "  Connection FAILED"

# Check pgAdmin
echo "✓ pgAdmin:"
curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:5050

# Check Debezium
echo "✓ Debezium:"
curl -s http://localhost:8083/connectors >/dev/null 2>&1 && echo "  API OK" || echo "  API FAILED"

# Check Kafka UI  
echo "✓ Kafka UI:"
curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:8080

echo ""
echo "All services deployed with passwords from sensitive-values vault"
