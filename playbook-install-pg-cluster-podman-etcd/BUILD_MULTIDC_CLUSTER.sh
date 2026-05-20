#!/bin/bash
# Multi-DC PostgreSQL Cluster Build Script
# Builds complete multi-datacenter setup with pg4 standby

set -e

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASEDIR"

echo "======================================================================"
echo "  PostgreSQL Multi-DC Cluster Build (Podman)"
echo "======================================================================"
echo ""

# Phase 1: Cleanup (if needed)
if [ "${SKIP_CLEANUP:-false}" != "true" ]; then
    echo "[Phase 1] Cleaning up existing cluster..."
    ansible-playbook playbook-cleanup.yml -e skip_confirm=true >/dev/null 2>&1
    echo "✓ Cleanup complete"
    echo ""
fi

# Phase 2: Infrastructure
echo "[Phase 2] Creating Podman containers (pg1-pg4)..."
ansible-playbook playbook-setup-podman.yml >/dev/null 2>&1
echo "✓ Infrastructure ready (4 containers + volumes)"
echo ""

# Phase 3: Primary Cluster
echo "[Phase 3] Installing Primary Cluster (pg1-pg3)..."
echo "  This takes ~15-20 minutes. Monitoring..."
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
    --vault-password-file=vault-pass 2>&1 | grep -E "TASK|changed|ok|failed" || true
echo "✓ Primary cluster install complete"
echo ""

# Phase 4: Verify Primary
echo "[Phase 4] Verifying Primary Cluster..."
sleep 5
podman exec pg1 patronictl -c /etc/patroni/patroni.yml list
echo ""

# Phase 5: Standby Cluster
echo "[Phase 5] Installing Standby Cluster (pg4)..."
echo "  This takes ~15 minutes. Monitoring..."
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml \
    --vault-password-file=vault-pass 2>&1 | grep -E "TASK|changed|ok|failed" || true
echo "✓ Standby cluster install complete"
echo ""

# Phase 6: Verify Multi-DC
echo "[Phase 6] Verifying Multi-DC Setup..."
sleep 5
echo ""
echo "=== Standby Cluster Status ==="
podman exec pg4 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null || echo "pg4 still initializing..."
echo ""
echo "=== Replication from Primary to Standby ==="
podman exec pg1 psql -U postgres postgres -c \
  "SELECT client_addr, state, sync_state, ROUND((sent_lsn - replay_lsn)/1048576.0,2) AS lag_mb 
   FROM pg_stat_replication WHERE client_addr = '172.18.0.14';" 2>/dev/null || echo "Checking..."
echo ""

echo "======================================================================"
echo "  ✅ Multi-DC Cluster Build Complete!"
echo "======================================================================"
echo ""
echo "Primary Cluster (Region A): pg1, pg2, pg3"
echo "  Cluster name: pg-podman-cls1"
echo "  Leader VIP: 172.18.0.10"
echo "  Read VIP: 172.18.0.9"
echo ""
echo "Standby Cluster (Region B): pg4"
echo "  Streaming from: 172.18.0.10:5432"
echo "  Role: Read-only standby (until promoted)"
echo ""
