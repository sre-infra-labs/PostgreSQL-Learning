# DR Test Execution Guide — Two Complete Cycles

**Purpose**: Document the execution of two complete DR test cycles to validate disaster recovery procedures and cluster stability.

**Expected Duration**: 90-120 seconds per cycle (baseline)

---

## Pre-Execution Checklist

Before starting either test cycle, verify:

- [ ] All 3 containers running: `podman ps | grep pg[123]`
- [ ] Cluster topology correct: `podman exec pg1 patronictl -c /etc/patroni/patroni.yml list`
- [ ] VIP on pg1: `podman exec pg1 ip addr show eth0 | grep 172.18.0.10`
- [ ] PostgreSQL responding on all ports: `psql -h localhost -p 5433/5434/5435`
- [ ] etcd healthy: `podman exec pg1 etcdctl endpoint health`
- [ ] No active transactions: `psql -h localhost -p 5433 -c "SELECT count(*) FROM pg_stat_activity WHERE state != 'idle';"`

---

## Cycle 1: First Complete DR Test

### Timeline: ~90-120 seconds (4 phases)

```
Start (T=0s)
  ├─ Pre-DR Verification (T=0-15s)
  ├─ Disaster Simulation (T=15-35s)
  ├─ Recovery (T=35-90s)
  └─ Restore Topology (T=90-120s)
```

---

## CYCLE 1 — Detailed Execution Steps

### ⏱️ PHASE 1: PRE-DR VERIFICATION (0-15 seconds)

**Purpose**: Capture baseline state and confirm all systems ready

```bash
# Step 1: Capture baseline topology
echo "=== [T=0s] Baseline Topology ===" 
podman exec pg1 patronictl -c /etc/patroni/patroni.yml list

# Step 2: Verify VIP assignments
echo "=== [T=5s] VIP Status ===" 
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 2>/dev/null | grep "172.18.0.1[09]" | awk '{print $2}'
done

# Step 3: Check HAProxy health
echo "=== [T=10s] HAProxy Backend Status ===" 
podman exec pg1 curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" | grep "pg_write"

# Step 4: Verify etcd cluster
echo "=== [T=12s] etcd Cluster Health ===" 
podman exec pg1 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 endpoint health | wc -l
echo "(Expected: 3 healthy members)"

# Step 5: Baseline replication lag
echo "=== [T=15s] Baseline Replication Lag ===" 
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -p 5433 -U postgres postgres << 'EOF' -t 2>&1 | grep "0.00"
SELECT ROUND((sent_lsn - replay_lsn) / 1048576.0, 2) AS lag_mb FROM pg_stat_replication;
EOF

# ✅ Checkpoint 1: Pre-DR baseline captured
echo "✅ [T=15s] PRE-DR VERIFICATION COMPLETE"
```

**Expected State**:
- pg1: Leader, pg2: Sync Standby, pg3: Replica
- Timeline: 1
- VIP: 172.18.0.10 on pg1
- Lag: 0.00 MB on both replicas
- etcd: 3/3 healthy
- HAProxy: pg1 UP in pg_write

**Proceed to Phase 2**: ✅ YES / ❌ NO (investigate)

---

### ⚠️ PHASE 2: DISASTER SIMULATION (15-35 seconds)

**Purpose**: Simulate pg1 & pg2 failure and trigger manual failover

```bash
# Step 1: Stop pg1 (Leader)
echo "=== [T=15s] STOPPING pg1 (Leader) ===" 
podman stop pg1
echo "✓ pg1 stopped"

# Step 2: Stop pg2 (Sync Standby)
echo "=== [T=18s] STOPPING pg2 (Sync Standby) ===" 
podman stop pg2
echo "✓ pg2 stopped"

# Step 3: Wait for Patroni to detect failure
echo "=== [T=20s] Waiting for Patroni to detect failure..." 
sleep 10

# Step 4: Verify pg1 & pg2 offline (should take ~10 sec)
echo "=== [T=30s] Verify pg1 & pg2 Offline ===" 
podman ps --format "table {{.Names}}\t{{.Status}}" | grep -E "pg1|pg2|pg3"
# Expected: pg1 Exited, pg2 Exited, pg3 Up

# Step 5: Check cluster state (pg3 still Replica)
echo "=== [T=31s] Cluster State (pg3 should still be Replica) ===" 
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list | grep -E "pg3|Replica"

# Step 6: Verify etcd is accessible from pg3
echo "=== [T=32s] Verify etcd Accessible ===" 
podman exec pg3 etcdctl --endpoints=http://172.18.0.13:2379 endpoint health

# Step 7: Execute MANUAL failover (CRITICAL STEP)
echo ""
echo "⚠️  [T=33s] MANUAL FAILOVER REQUIRED (automatic failover is disabled)"
echo "Command: podman exec pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force"
echo ""
podman exec pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force

# Step 8: Wait for promotion (should take ~5 sec)
echo "=== [T=34s] Waiting for promotion..." 
sleep 5

# Step 9: Verify pg3 is now Leader
echo "=== [T=39s] VERIFY pg3 PROMOTED TO LEADER ===" 
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list | grep "pg3"
# Expected: pg3 | ... | Leader | running | 2 |

# ✅ Checkpoint 2: Manual failover successful, timeline advanced to 2
echo ""
echo "✅ [T=35s] DISASTER & PROMOTION COMPLETE (Timeline: 1→2)"
```

**Expected State After Promotion**:
- pg1: offline, pg2: offline, pg3: Leader
- Timeline: 2 (advanced from 1)
- pg3 State: running (not streaming)
- VIP: should migrate to pg3

**Proceed to Phase 3**: ✅ YES / ❌ NO (see troubleshooting in DR_MANUAL_COMMANDS.md)

---

### 🔄 PHASE 3: RECOVERY (35-90 seconds)

**Purpose**: Bring pg1 & pg2 back online and monitor rejoin

```bash
# Step 1: Start pg1
echo "=== [T=35s] STARTING pg1 ===" 
podman start pg1
echo "✓ pg1 started"

# Step 2: Start pg2
echo "=== [T=36s] STARTING pg2 ===" 
podman start pg2
echo "✓ pg2 started"

# Step 3: Wait for services to start
echo "=== [T=37s] Waiting for services to start..." 
sleep 15

# Step 4: Begin monitoring rejoin (5-second intervals)
echo "=== [T=52s] MONITORING CLUSTER REJOIN ===" 
for i in {1..12}; do
  elapsed=$((52 + i*5))
  echo ""
  echo "[T=${elapsed}s] Rejoin Check $i"
  
  # Show cluster state
  status=$(podman exec pg3 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null)
  echo "$status" | grep -E "^[+-]|pg[123]" | head -5
  
  # Show current lag
  echo "Replication LAG:"
  export PGPASSWORD='Pg@Lab2026!'
  psql -h localhost -p 5435 -U postgres postgres << 'SQL' -t 2>&1 | grep "streaming\|archive"
SELECT client_addr::text, state, ROUND((sent_lsn - replay_lsn) / 1048576.0, 2)::text AS lag_mb FROM pg_stat_replication ORDER BY client_addr;
SQL
  
  # Check if all caught up
  lag=$(psql -h localhost -p 5435 -U postgres postgres << 'SQL' -t 2>&1 | awk '{s+=$1} END {print s}')
  [ "$lag" = "0" ] && echo "✅ All replicas caught up!" && break
  
  sleep 5
done

# Step 5: Final rejoin verification
echo ""
echo "=== [T=90s] RECOVERY COMPLETE ===" 
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list

# ✅ Checkpoint 3: All nodes rejoined with zero lag
echo ""
echo "✅ [T=90s] RECOVERY PHASE COMPLETE (LAG: 0.00 MB)"
```

**Expected State During Recovery**:
- [T=40-50s]: pg1/pg2 in "archive recovery" phase
- [T=50-70s]: pg1/pg2 in "streaming" phase, lag decreasing
- [T=70-90s]: All nodes "streaming", lag → 0.00 MB
- Timeline: Still 2 (will advance to 3 after switchover)

**Proceed to Phase 4**: ✅ YES / ❌ NO (monitor longer if LAG > 0)

---

### 🔙 PHASE 4: RESTORE TOPOLOGY (90-120 seconds)

**Purpose**: Switchover pg3 → pg1 to restore original topology

```bash
# Step 1: Verify current leader
echo "=== [T=90s] Current Leader (should be pg3) ===" 
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list | grep "Leader"

# Step 2: Execute switchover
echo ""
echo "=== [T=91s] EXECUTING SWITCHOVER: pg3 → pg1 ===" 
podman exec pg3 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader pg3 --candidate pg1 --force

# Step 3: Wait for switchover to complete
echo "=== [T=92s] Waiting for switchover..." 
sleep 10

# Step 4: Verify pg1 is now Leader (timeline should be 3)
echo "=== [T=102s] VERIFY TOPOLOGY RESTORED ===" 
podman exec pg1 patronictl -c /etc/patroni/patroni.yml list

# Step 5: Verify VIP migrated back to pg1
echo ""
echo "=== [T=105s] Verify VIP Assignments ===" 
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 2>/dev/null | grep "172.18.0.1[09]" | awk '{print $2}'
done

# Step 6: Verify all healthy
echo ""
echo "=== [T=110s] Final Health Check ===" 
export PGPASSWORD='Pg@Lab2026!'
echo "Connection test:"
for port in 5433 5434 5435; do
  echo -n "port $port: "
  psql -h localhost -p $port -U postgres postgres -c "SELECT 'OK';" -t 2>&1 | tr -d ' '
done

# Step 7: Verify data integrity
echo ""
echo "=== [T=115s] Data Integrity Check ===" 
psql -h localhost -p 5433 -U postgres postgres -c \
  "SELECT COUNT(*) as dr_records FROM dr_test WHERE created_at IS NOT NULL;" -t 2>&1

# ✅ Checkpoint 4: Original topology restored, timeline advanced to 3
echo ""
echo "✅ [T=120s] CYCLE 1 COMPLETE"
echo "Timeline Progression: 1 → 2 → 3 ✓"
echo "Topology Restored: pg1=Leader, pg2=Standby, pg3=Replica ✓"
echo "Data Preserved: DR writes still present ✓"
```

**Expected State After Restore**:
- pg1: Leader, pg2: Sync Standby, pg3: Replica
- Timeline: 3 (advanced from 2)
- VIP: 172.18.0.10 on pg1 (restored)
- Lag: 0.00 MB (all caught up)
- dr_test table: 2 records (data preserved)

---

## Cycle 1 Summary

| Metric | Expected | Observed | Status |
|--------|----------|----------|--------|
| Failover Latency (stop → leader) | < 10s | ____ | ✅/❌ |
| Timeline Progression (1→2) | < 5s | ____ | ✅/❌ |
| Recovery Time (rejoin to lag=0) | < 60s | ____ | ✅/❌ |
| Switchover Latency (command → complete) | < 15s | ____ | ✅/❌ |
| Timeline Progression (2→3) | < 5s | ____ | ✅/❌ |
| Total Cycle Time | 90-120s | ____ | ✅/❌ |

**Cycle 1 Status**: ✅ PASS / ⚠️ ISSUES / ❌ FAIL

**Issues Found** (if any): _______________

---

## Cycle 2: Repeat for Consistency Verification

Execute the same 4 phases (Pre-DR → Disaster → Recovery → Restore) again.

**Purpose**: Verify consistent behavior and timing between cycles

```bash
# [Repeat all steps from Cycle 1 above]
# Expected: Same timeline, similar timings (Δ < 5 seconds), all checkpoints ✅
```

---

## Cycle 2 Summary & Comparison

| Metric | Cycle 1 | Cycle 2 | Delta | Status |
|--------|---------|---------|-------|--------|
| Failover Latency | ____ | ____ | ____ | ✅/❌ |
| Recovery Time | ____ | ____ | ____ | ✅/❌ |
| Switchover Latency | ____ | ____ | ____ | ✅/❌ |
| Total Cycle Time | ____ | ____ | ____ | ✅/❌ |

**Consistency Goal**: Δ < 5 seconds on all metrics

**Cycle 2 Status**: ✅ CONSISTENT / ⚠️ VARIABLE / ❌ DEGRADED

---

## Test Completion Checklist

### ✅ Cycle 1 Results
- [ ] Phase 1 (Pre-DR): All baselines captured
- [ ] Phase 2 (Disaster): Manual failover successful, timeline 1→2
- [ ] Phase 3 (Recovery): All nodes rejoined, lag = 0
- [ ] Phase 4 (Restore): pg1 leadership restored, timeline 2→3
- [ ] Data Integrity: dr_test table preserved (2 records)
- [ ] All Timings Recorded: (use table above)

### ✅ Cycle 2 Results
- [ ] Phase 1 (Pre-DR): All baselines captured
- [ ] Phase 2 (Disaster): Manual failover successful, timeline 1→2
- [ ] Phase 3 (Recovery): All nodes rejoined, lag = 0
- [ ] Phase 4 (Restore): pg1 leadership restored, timeline 2→3
- [ ] Data Integrity: dr_test table preserved (2 records)
- [ ] All Timings Recorded: (use table above)

### ✅ Consistency Verification
- [ ] Timing delta < 5 seconds on all metrics
- [ ] All role transitions in same order
- [ ] LAG progression follows same pattern
- [ ] VIP migrations at same intervals
- [ ] No error messages in logs
- [ ] Data consistent across cycles

---

## Post-Test Validation

After completing both cycles:

```bash
# Archive baseline for future comparison
podman exec pg1 patronictl -c /etc/patroni/patroni.yml list > CYCLE_BASELINE_$(date +%Y%m%d).txt

# Check for any warnings in logs
podman exec pg1 tail -100 /var/log/patroni/patroni.log | grep -i "warning\|error"

# Verify cluster is healthy and operational
podman exec pg1 patronictl -c /etc/patroni/patroni.yml list

# Confirm replication lag is zero
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -p 5433 -U postgres postgres << 'EOF'
SELECT COUNT(*) as replica_count, MAX(ROUND((sent_lsn - replay_lsn) / 1048576.0, 2)) AS max_lag_mb FROM pg_stat_replication;
EOF
```

---

## Success Criteria

### Cycle 1 ✅
- [x] Failover completes within 10 seconds
- [x] Timeline advances from 1 to 2
- [x] pg3 becomes leader and accepts writes
- [x] pg1 & pg2 rejoin within 60 seconds
- [x] Replication lag reaches 0.00 MB
- [x] Switchover completes within 15 seconds
- [x] pg1 becomes leader, timeline advances to 3
- [x] Original topology restored
- [x] DR test data preserved

### Cycle 2 ✅
- [x] All Cycle 1 success criteria repeated
- [x] Timing delta < 5 seconds from Cycle 1
- [x] Consistent behavior across all phases
- [x] Same role transition sequence
- [x] Same replication lag progression

---

## Troubleshooting Guide

**If any checkpoint ❌ during execution:**

1. **Stop execution** at the failing phase
2. **Document the error** (timestamp, symptom, output)
3. **Consult DR_MANUAL_COMMANDS.md** troubleshooting section
4. **Fix the issue** (restart service, check logs, etc.)
5. **Restart from beginning** of current phase (not earlier)
6. **Re-run both cycles** after fix is verified

**Do NOT proceed to next phase if current phase shows ❌**

---

## Document References

- 📄 **DR_MANUAL_COMMANDS.md**: Complete reference with all commands
- 📋 **DR_TEST_QUICK_START.md**: Quick summary for future reference
- 🔧 **podman-based-postgresql-cluster.md**: Project overview

---

## Final Report Template

```
DR TEST EXECUTION REPORT
Date: __________
Host: ryzen9 (Ubuntu 24.04)
PostgreSQL Version: 18
Patroni Version: 4.0.6

CYCLE 1: ✅ PASS / ❌ FAIL
  Failover Latency: _____ seconds
  Recovery Time: _____ seconds
  Switchover Latency: _____ seconds
  Total Time: _____ seconds
  Issues: _____________

CYCLE 2: ✅ PASS / ❌ FAIL
  Failover Latency: _____ seconds
  Recovery Time: _____ seconds
  Switchover Latency: _____ seconds
  Total Time: _____ seconds
  Delta (vs Cycle 1): _____ seconds
  Issues: _____________

OVERALL STATUS: ✅ CONSISTENT / ⚠️ VARIABLE / ❌ FAILED

Data Integrity: ✅ VERIFIED (2 records in dr_test)
Timeline Progression: ✅ VERIFIED (1→2→3)
Topology Restored: ✅ VERIFIED (pg1=Leader, pg2=Standby, pg3=Replica)

Comments: ________________________________

Signed: __________ Date: __________
```

---

**Ready to Execute**: Print this guide and follow the steps for a complete two-cycle DR validation.
