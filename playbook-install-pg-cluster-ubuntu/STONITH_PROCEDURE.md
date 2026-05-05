# STONITH & Graceful Standby Promotion

## Your Question
"How to make source cluster down for a graceful standby promotion?"

Reference: https://patroni.readthedocs.io/en/latest/ha_multi_dc.html

## Answer: The STONITH Procedure

**STONITH** = "Shoot The Other Node In The Head" — safely shut down the primary before promoting standby.

### Why STONITH is Critical

If you promote pg4 while pg1/pg2/pg3 is still running:
- ❌ Split-brain: Two independent primaries (different timelines)
- ❌ Data loss: Writes on both clusters cannot reconcile
- ❌ Corruption: pg_rewind may fail

**Solution**: Pause → Wait for catch-up → Stop primary (STONITH) → Promote standby

---

## Complete Graceful Promotion (3 Phases)

### Phase 1: Graceful STONITH (3 steps)

Step 1: Pause primary cluster with --wait flag
  docker exec pg1 patronictl -c /etc/patroni/patroni.yml pause --wait
  (Waits for synchronous replicas to acknowledge all WAL)

Step 2: Verify pg4 caught up (LAG = 0 MB)
  watch -n 2 'docker exec pg4 patronictl -c /etc/patroni/patroni.yml list'
  (Press Ctrl+C when LAG = 0 MB)

Step 3: Stop primary cluster services (STONITH)
  docker stop pg1 pg2 pg3
  (Safe to stop now — all data is replicated)

### Phase 2: Promote Standby to Primary

Remove standby_cluster config:
  docker exec pg4 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 \
    --force --set standby_cluster=null

Verify promotion:
  docker exec pg4 patronictl -c /etc/patroni/patroni.yml list
  Expected: pg4 shows "Leader" role

### Phase 3: Failback to Original Primary (when recovered)

Step 1: Bring primary back online
  docker start pg1 pg2 pg3

Step 2: Convert to standby of pg4 (use PRIMARY VIP 172.18.0.10)
  docker exec pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 \
    --force --set "standby_cluster={host: 172.18.0.10, port: 5432}"

Step 3: Wait for catch-up (LAG = 0 MB)
  watch -n 5 'docker exec pg4 patronictl -c /etc/patroni/patroni.yml list'

Step 4: Failover back to pg1
  docker exec pg4 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
    --leader pg4 --candidate pg1 --force

Step 5: Restore pg4 as standby (use PRIMARY VIP 172.18.0.10)
  docker exec pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 \
    --force --set "standby_cluster={host: 172.18.0.10, port: 5432}"

---

## Real-World Scenarios

**Scenario A: Network Partition (Primary is UP)**
  1. Pause primary with --wait: patronictl pause --wait
     (Waits for sync replicas to acknowledge WAL)
  2. Verify catch-up: LAG = 0 MB on pg4
  3. STONITH: docker stop pg1 pg2 pg3
     (Guaranteed safe — all data replicated)
  4. Promote: set standby_cluster=null

**Scenario B: Hardware Failure (Primary is DOWN)**
  1. Verify primary is unreachable (already down)
  2. Promote immediately: set standby_cluster=null
  3. No pause/STONITH needed (primary already failed)

**Scenario C: Failback After Recovery**
  1. Start recovered primary: docker start pg1 pg2 pg3
  2. Convert to standby of pg4: set standby_cluster={host: 172.18.0.10, port: 5432} (PRIMARY VIP)
  3. Wait for catch-up: LAG = 0 MB
  4. Failover back to pg1: patronictl switchover
  5. Restore pg4 as standby: set standby_cluster={host: 172.18.0.10, port: 5432} (PRIMARY VIP)

---

## Documentation Added

File: docker-based-postgresql-cluster.md

New sections:
- "Critical: STONITH Requirement" — split-brain risk
- "Step 0: Graceful STONITH Procedure" — detailed 3-step process
- "Quick Reference: STONITH & Graceful Standby Promotion" — 5-minute checklist
- "Scenario A, B, C" — real-world examples with exact commands
- Visual split-brain diagram (Wrong vs. Right)

All include expected outputs and safety checks.
