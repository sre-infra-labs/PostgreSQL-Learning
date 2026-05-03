# DR Scenario Testing — Quick Start Guide

## Overview

Test **pg3 (replica)** becoming the active leader when **pg1 (leader)** and **pg2 (sync standby)** fail.

## Quick Commands

### Option 1: Automated Test Script (Recommended)

```bash
cd playbook-install-pg-cluster-podman/

# Run complete DR test cycle
bash DR_TEST_SCENARIO.sh all

# Or run individual phases
bash DR_TEST_SCENARIO.sh normal    # Check normal state
bash DR_TEST_SCENARIO.sh dr        # Simulate disaster
bash DR_TEST_SCENARIO.sh recover   # Bring nodes back
bash DR_TEST_SCENARIO.sh restore   # Restore original topology
```

### Option 2: Manual Commands

#### Pre-DR: Verify Normal State

```bash
export PGPASSWORD='Pg@Lab2026!'
podman exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

#### Simulate Disaster (Stop pg1 & pg2)

```bash
echo "Stopping pg1 and pg2..."
podman stop pg1 pg2
sleep 10

echo "Verify pg1 & pg2 are DOWN, pg3 is still REPLICA:"
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list

# ⚠️  IMPORTANT: Automatic failover is DISABLED - MANUAL promotion required
echo ""
echo "Promoting pg3 to Leader (MANUAL - automatic failover disabled)..."
podman exec pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force

sleep 5

echo "Confirming pg3 is now the Leader:"
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
```

**Key Point**: 
- ⚠️  **Automatic failover is DISABLED** in this cluster
- ⚠️  **pg3 is async (nosync: true)** - NOT eligible for automatic promotion
- ✓ **MANUAL command REQUIRED**: `patronictl failover pg-docker-cls1 --force`
- ✓ After promotion, VIP (172.18.0.10) automatically migrates to pg3

#### Test pg3 Accepts Writes (DR Mode)

```bash
export PGPASSWORD='Pg@Lab2026!'

# Direct connection
psql -h localhost -p 5435 -U postgres postgres -c \
  "CREATE TABLE IF NOT EXISTS dr_test AS SELECT now();
   INSERT INTO dr_test SELECT now();
   SELECT COUNT(*) FROM dr_test;"
```

#### Recover (Start pg1 & pg2)

```bash
echo "Starting pg1 and pg2..."
podman start pg1 pg2
sleep 15

echo "Waiting for rejoin (30-60 sec)..."
for i in {1..30}; do
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
  sleep 2
done
```

#### Restore Original Topology (Optional)

```bash
echo "Switchover: pg3 → pg1"
podman exec pg3 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader pg3 --candidate pg1 --force

sleep 10
podman exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

## Expected Results

| Phase | State | pg1 | pg2 | pg3 | Manual Action | Notes |
|-------|-------|-----|-----|-----|--------------|----|
| **Normal** | Running | Leader | Sync Standby | Replica | — | Initial state |
| **After Stop** | pg1/pg2 stopped | ✗ OFFLINE | ✗ OFFLINE | **Replica** | REQUIRED | pg3 still Replica (auto-failover disabled) |
| **After Promotion** | Manual failover | ✗ OFFLINE | ✗ OFFLINE | **Leader** | `patronictl failover` | pg3 manually promoted |
| **Recovery** | Started pg1/pg2 | Replica (catching up) | Replica (catching up) | Leader | — | Cluster reforming |
| **Restored** | Switchover done | **Leader** | Sync Standby | Replica | `patronictl switchover` | Original topology restored |

**Key Difference**: Unlike clusters with automatic failover, **manual `patronictl failover` command is REQUIRED** to promote pg3 because:
- ⚠️ Automatic failover is DISABLED
- ⚠️ pg3 is async (nosync: true) — not eligible for automatic election

## Monitoring During DR

```bash
# Watch VIP migration (run in separate terminal)
watch -n 2 'for n in pg1 pg2 pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 2>/dev/null | grep "inet "
done'

# Watch Patroni status
watch -n 2 'podman exec pg3 patronictl -c /etc/patroni/patroni.yml list'

# Watch PostgreSQL replication lag
watch -n 5 'psql -h localhost -p 5433 -U postgres postgres -c \
  "SELECT client_addr, state, \
          EXTRACT(EPOCH FROM replay_lag)::INT as lag_sec
   FROM pg_stat_replication;"'
```

## Key Points

⚠️ **MANUAL PROMOTION REQUIRED** — Automatic failover is DISABLED  
⚠️ **pg3 is async (nosync: true)** — NOT eligible for automatic election  
✓ **Manual command**: `patronictl failover pg-docker-cls1 --force`  
✓ **VIP (172.18.0.10) follows pg3** automatically after promotion  
✓ **Writes safe on pg3** — data preserved when pg1/pg2 rejoin  
✓ **Zero application changes** — apps reconnect to same VIP  
✓ **Replication catches up** — LAG in MB → 0 after recovery  

## Troubleshooting

### pg3 Not Promoted to Leader

**Symptom**: pg3 remains Replica even after pg1/pg2 stopped

**Check**: 
- Patroni might be paused: `podman exec pg3 patronictl -c /etc/patroni/patroni.yml list | grep pause`
- Resume if needed: `podman exec pg3 patronictl -c /etc/patroni/patroni.yml resume`
- etcd connectivity: `podman exec pg3 etcdctl --endpoints=http://172.18.0.13:2379 endpoint health`

### Switchover Fails

**Symptom**: `Error: switchover is already in progress` or similar

**Fix**: Wait a few seconds and retry:
```bash
sleep 5
podman exec pg3 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader pg3 --candidate pg1 --force
```

### VIP Stuck on Wrong Node

**Symptom**: VIP still on pg1 even though it's stopped

**Fix**: Restart Keepalived on pg3:
```bash
podman exec pg3 systemctl restart keepalived
sleep 5
podman exec pg3 ip addr show eth0 | grep "inet "  # Should show 172.18.0.10
```

## Full Documentation

See `podman-based-postgresql-cluster.md` for detailed information about:
- Failover Testing
- Disaster Recovery Concepts
- VIP Management
- Replication Lag Monitoring
- etcd Health

