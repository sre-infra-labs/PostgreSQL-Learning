#!/bin/bash

# Debezium CDC Infrastructure Deployment Script
# This script deploys the complete CDC infrastructure using Ansible

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_FILE="${SCRIPT_DIR}/deployment_$(date +%Y%m%d_%H%M%S).log"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Debezium CDC Learning Infrastructure Deployment               ║"
echo "║  Log: $LOG_FILE                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
echo "1️⃣  Checking prerequisites..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker."
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! command -v docker compose &> /dev/null; then
    echo "❌ Docker Compose not found. Please install Docker Compose."
    exit 1
fi

if ! command -v ansible-playbook &> /dev/null; then
    echo "❌ Ansible not found. Please install Ansible."
    exit 1
fi

echo "✓ All prerequisites found"
echo ""

# Verify vault file
echo "2️⃣  Verifying vault configuration..."
if [ ! -f "vault-pass" ]; then
    echo "❌ vault-pass file not found"
    exit 1
fi

if [ ! -f "sensitive-values" ]; then
    echo "❌ sensitive-values file not found"
    exit 1
fi

# Try to decrypt vault
if ! ansible-vault view sensitive-values --vault-password-file=vault-pass > /dev/null 2>&1; then
    echo "❌ Failed to decrypt sensitive-values. Check vault password."
    exit 1
fi

echo "✓ Vault configured correctly"
echo ""

# Deploy
echo "3️⃣  Starting full stack deployment..."
echo "This may take 5-10 minutes on first run (Docker image pulls)"
echo ""

{
    echo "=== Deployment Started: $(date) ==="
    echo ""
    ansible-playbook -i hosts.yml playbook-deploy-all.yml --vault-password-file=vault-pass
    DEPLOY_STATUS=$?
    echo ""
    echo "=== Deployment Completed: $(date) ==="
    echo "=== Exit Code: $DEPLOY_STATUS ==="
} | tee -a "$LOG_FILE"

FINAL_STATUS=${PIPESTATUS[0]}

if [ $FINAL_STATUS -eq 0 ]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  ✅ Deployment Completed Successfully!                         ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Log saved to: $LOG_FILE"
    echo ""
    echo "4️⃣  Checking container status..."
    docker ps | grep cdc || true
    echo ""
    echo "✅ Access services at:"
    echo "   - Kafka UI: http://localhost:8080"
    echo "   - Debezium: http://localhost:8083/connectors"
    echo "   - pgAdmin: http://localhost:5050"
    exit 0
else
    echo ""
    echo "❌ Deployment failed. Check the output above for errors."
    echo "Log saved to: $LOG_FILE"
    exit 1
fi
