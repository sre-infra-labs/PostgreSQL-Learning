# DR Scenario Testing — Manual Commands Reference

**Setup**: Automatic failover is DISABLED, pg3 is async (nosync: true)  
**Requirement**: MANUAL commands to promote pg3 as leader during DR

---

## Pre-DR: Verify Normal State

### Step 1: Check Cluster Topology

```bash
podman exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

**Expected Output**:
```
+ Cluster: pg-docker-cls1 (xxx) --+----+-----------+--------------+
| Member | Host        | Role    | State     | TL | Lag in MB | Tags         |
+--------+-------------+---------+-----------+----+-----------+--------------+
| pg1    | 172.18.0.11 | Leader  | running   |  1 |           |              |
| pg2    | 172.18.0.12 | Sync Standby | streaming |  1 |  0  |              |
| pg3    | 172.18.0.13 | Replica | streaming |  1 |  0  | nosync: true |
+--------+-------------+---------+-----------+----+-----------+--------------+
```

### Step 2: Verify VIP Assignments

```bash
# Check which node has primary VIP (172.18.0.10)
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 2>/dev/null | grep "inet "
done
```

**Expected Output**:
```
pg1: inet 172.18.0.11/16 brd 172.18.255.255 scope global eth0
pg1: inet 172.18.0.10/32 scope global secondary eth0:vip    ← PRIMARY VIP
pg2: inet 172.18.0.12/16 brd 172.18.255.255 scope global eth0
pg3: inet 172.18.0.13/16 brd 172.18.255.255 scope global eth0
```

### Step 3: Test Connections to All Nodes

```bash
export PGPASSWORD='Pg@Lab2026!'

# Test pg1 (Leader)
psql -h localhost -p 5433 -U postgres postgres -c \
  "SELECT inet_server_addr() AS node, pg_is_in_recovery() AS is_replica;"

# Test pg2 (Sync Standby)
psql -h localhost -p 5434 -U postgres postgres -c \
  "SELECT inet_server_addr() AS node, pg_is_in_recovery() AS is_replica;"

# Test pg3 (Replica)
psql -h localhost -p 5435 -U postgres postgres -c \
  "SELECT inet_server_addr() AS node, pg_is_in_recovery() AS is_replica;"
```

**Expected Output**:
```
      node      | is_replica
-----------------+------------
 172.18.0.11    | f          ← pg1 is NOT in recovery (Leader)
 172.18.0.12    | t          ← pg2 IS in recovery (Standby)
 172.18.0.13    | t          ← pg3 IS in recovery (Replica)
```

### Step 4: Verify Patroni Health Endpoints

```bash
# Check /primary endpoint (returns 200 only on leader)
for port in 8011 8012 8013; do
  node=""
  [ "$port" = "8011" ] && node="pg1"
  [ "$port" = "8012" ] && node="pg2"
  [ "$port" = "8013" ] && node="pg3"
  echo -n "$node /primary: "
  curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:$port/primary
done
```

**Expected Output**:
```
pg1 /primary: HTTP 200    ← Only pg1 returns 200
pg2 /primary: HTTP 503
pg3 /primary: HTTP 503
```

### Step 5: Verify HAProxy Backend Health

```bash
# Check HAProxy write pool (should have pg1 as UP)
podman exec pg1 curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" | grep -E "^pg_write|^pg_read" | cut -d, -f1,2,18
```

**Expected Output**:
```
pg_write,172.18.0.11:5433,UP
pg_read,172.18.0.12:5434,UP
pg_read,172.18.0.13:5435,UP
```

### Step 6: Verify etcd Cluster is Healthy

```bash
podman exec pg1 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health
```

**Expected Output**:
```
http://172.18.0.11:2379 is healthy: successfully committed proposal: took = 10.234ms
http://172.18.0.12:2379 is healthy: successfully committed proposal: took = 10.456ms
http://172.18.0.13:2379 is healthy: successfully committed proposal: took = 10.567ms
```

### Step 7: Capture Baseline Replication State

```bash
export PGPASSWORD='Pg@Lab2026!'

psql -h localhost -p 5433 -U postgres postgres << 'EOF'
SELECT 
  client_addr,
  state,
  sync_state,
  ROUND((sent_lsn - replay_lsn) / 1048576.0, 2) AS lag_mb,
  EXTRACT(EPOCH FROM pg_current_wal_lsn() - '0/0'::pg_lsn) AS wal_lsn_epoch
FROM pg_stat_replication
ORDER BY client_addr;
EOF
```

**Expected Output**:
```
  client_addr  | state     | sync_state | lag_mb | wal_lsn_epoch
-----------------+-----------+------------+--------+---------------
 172.18.0.12  | streaming | sync       |   0.00 |    xxxxx.xxx
 172.18.0.13  | streaming | async      |   0.00 |    xxxxx.xxx
(2 rows)
```

---

## ⚠️ DISASTER SCENARIO: Stop pg1 & pg2

### Step 1: Stop pg1 (Leader)

```bash
podman stop pg1
```

**Output**: `pg1`

### Step 2: Stop pg2 (Sync Standby)

```bash
podman stop pg2
```

**Output**: `pg2`

### Step 3: Wait for Patroni to Detect Failure

```bash
sleep 10
```

### Step 4: Verify pg1 & pg2 are DOWN

```bash
podman ps --format "table {{.Names}}\t{{.Status}}"
```

**Expected Output**:
```
NAMES       STATUS
pg1         Exited (0) about 15 seconds ago
pg2         Exited (0) about 10 seconds ago
pg3         Up 5 minutes
```

### Step 5: Check Cluster State (pg3 Still Replica)

```bash
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
```

**Expected Output**:
```
+ Cluster: pg-docker-cls1 (xxx) --+---------+----------+
| Member | Host        | Role    | State   | TL | Lag in MB |
+--------+-------------+---------+---------+----+-----------+
| pg1    | 172.18.0.11 | Leader  | offline |  1 |           |
| pg2    | 172.18.0.12 | Sync Standby | offline |  1 |     |
| pg3    | 172.18.0.13 | Replica | streaming |  1 |  0  |
+--------+-------------+---------+---------+----+-----------+
```

**⚠️ Notice**: pg3 is still Replica (NOT promoted automatically)

### Step 6: Verify etcd is Accessible from pg3

```bash
podman exec pg3 etcdctl --endpoints=http://172.18.0.13:2379 endpoint health
```

**Expected Output**:
```
http://172.18.0.13:2379 is healthy: successfully committed proposal: took = 10.234ms
```

### Step 7: Verify pg3 Can Write to DCS

```bash
podman exec pg3 patronictl -c /etc/patroni/patroni.yml show-config
```

**Expected Output**:
```
loop_wait: 10
ttl: 30
...
[Shows full Patroni configuration from DCS - etcd]
```

If this fails, etcd is not accessible and promotion will fail. Check Step 6 before proceeding.

---

## ✅ MANUAL PROMOTION: Elect pg3 as Leader

### Step 1: Execute Manual Failover Command

```bash
podman exec pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force
```

**Output**:
```
Failover scheduled.
```

### Step 2: Wait for Promotion to Complete

```bash
sleep 5
```

### Step 3: Verify pg3 is Now Leader

```bash
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
```

**Expected Output**:
```
+ Cluster: pg-docker-cls1 (xxx) --+---------+----------+
| Member | Host        | Role    | State   | TL | Lag in MB |
+--------+-------------+---------+---------+----+-----------+
| pg1    | 172.18.0.11 | Leader  | offline |  1 |           |
| pg2    | 172.18.0.12 | Sync Standby | offline |  1 |     |
| pg3    | 172.18.0.13 | Leader  | running |  2 |           | ✓ PROMOTED
+--------+-------------+---------+---------+----+-----------+
```

**✓ Key Points**:
- Timeline (TL) incremented from 1 to 2 (failover signature)
- pg3 State changed from "streaming" to "running"
- pg3 Role changed from "Replica" to "Leader"

### Step 3b: Verify pg3 Can Perform Writes (Critical Test)

```bash
export PGPASSWORD='Pg@Lab2026!'

podman exec pg3 psql -U postgres postgres -c \
  "SELECT is_wal_replay_paused() AS replay_paused, pg_is_in_recovery() AS is_replica;"
```

**Expected Output**:
```
 replay_paused | is_replica
---------------+------------
 f             | f          ← NOT in recovery, can accept writes
(1 row)
```

If `is_replica` is `t`, promotion failed. Do NOT proceed with writes.

### Step 4: Verify VIP Migrated to pg3

```bash
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 2>/dev/null | grep "172.18" | awk '{print $2}'
done
```

**Expected Output**:
```
pg1: 172.18.0.11/16
pg1: 172.18.0.10/32        ← VIP was here before
pg2: 172.18.0.12/16
pg3: 172.18.0.13/16
pg3: 172.18.0.10/32        ✓ VIP MIGRATED to pg3
```

### Step 5: Verify pg3 is PRIMARY (accepts writes)

```bash
export PGPASSWORD='Pg@Lab2026!'

podman exec pg3 psql -U postgres postgres -c \
  "SELECT inet_server_addr() AS node, pg_is_in_recovery() AS is_replica, now();"
```

**Expected Output**:
```
      node      | is_replica |              now
-----------------+------------+-------------------------------
 172.18.0.13    | f          | 2026-05-03 15:55:30.123456+05:30  ✓ NOT in recovery
```

---

## 📝 DR MODE ACTIVE: Test pg3 Accepts Writes

### Step 1: Create DR Test Table and Insert Data

```bash
export PGPASSWORD='Pg@Lab2026!'

psql -h localhost -p 5435 -U postgres postgres << 'EOF'
CREATE TABLE IF NOT EXISTS dr_test (
  id SERIAL PRIMARY KEY,
  event TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO dr_test (event) VALUES 
  ('DR mode activated - pg3 is now leader'),
  ('Data written during DR on ' || now()::TEXT);

SELECT COUNT(*) as total_records, MAX(created_at) as latest FROM dr_test;
EOF
```

**Expected Output**:
```
 total_records |              latest
---------------+-------------------------------
             2 | 2026-05-03 15:55:30.123456+05:30
```

### Step 2: Verify Data Persists

```bash
export PGPASSWORD='Pg@Lab2026!'

psql -h localhost -p 5435 -U postgres postgres -c \
  "SELECT id, event, created_at FROM dr_test ORDER BY id;"
```

**Expected Output**:
```
 id |                            event                            |              created_at
----+--------------------------------------------------------------+-------------------------------
  1 | DR mode activated - pg3 is now leader                       | 2026-05-03 15:55:20.123456+05:30
  2 | Data written during DR on 2026-05-03 15:55:30.123456+05:30 | 2026-05-03 15:55:30.123456+05:30
(2 rows)
```

### Step 3: Verify Patroni Health Endpoints

```bash
# Check /primary endpoint
echo -n "pg3 /primary: "
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8013/primary

# Check /replica endpoint (should return 503 - no replicas now)
echo -n "pg3 /replica: "
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8013/replica
```

**Expected Output**:
```
pg3 /primary: HTTP 200    ✓ pg3 is primary
pg3 /replica: HTTP 503    ✓ No replicas available (pg1/pg2 offline)
```

### Step 4: Verify HAProxy Write Pool is Healthy

```bash
podman exec pg3 curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" | grep -E "^pg_write" | cut -d, -f1,2,18
```

**Expected Output**:
```
pg_write,172.18.0.13:5435,UP   ✓ pg3 is the write backend
```

### Step 5: Verify pgBouncer Connectivity via VIP

```bash
export PGPASSWORD='Pg@Lab2026!'

# Test connection through VIP:6432 (pgBouncer on leader)
psql -h 172.18.0.10 -p 6435 -U postgres postgres -c "SELECT now();" 2>&1 | head -5
```

**Expected Output**:
```
              now
-------------------------------
 2026-05-03 15:55:30.123456+05:30
```

**Note**: Connection should work through VIP→pgBouncer→pg3 PostgreSQL

---

## 🔄 RECOVERY: Bring pg1 & pg2 Back Online

### Step 1: Start pg1 (will rejoin as Replica)

```bash
podman start pg1
```

**Output**: `pg1`

### Step 2: Start pg2 (will rejoin as Replica)

```bash
podman start pg2
```

**Output**: `pg2`

### Step 3: Wait for Services to Start

```bash
sleep 15
```

### Step 4: Verify Containers are Running

```bash
podman ps --format "table {{.Names}}\t{{.Status}}"
```

**Expected Output**:
```
NAMES       STATUS
pg1         Up 5 seconds
pg2         Up 3 seconds
pg3         Up 10 minutes
```

### Step 5a: Monitor Cluster Rejoin with Timeline Tracking

```bash
# Monitor cluster state with detailed timeline/LSN info (run for 60+ seconds)
for i in {1..15}; do
  echo ""
  echo "=== Rejoin Check $i (elapsed: $((i*5)) sec) ==="
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml list | grep -E "Member|^[+|-]|pg[123]"
  
  # Show timeline explicitly
  echo ""
  echo "Current WAL position on pg3:"
  podman exec pg3 psql -U postgres postgres -c "SELECT pg_current_wal_lsn(), now();" -t 2>&1 | head -1
  sleep 5
done
```

**Expected State Transitions**:
```
[After 10-20 sec - Archive Recovery Phase]
| pg1    | 172.18.0.11 | Replica | in archive recovery | 1 → 2 | 0   |
| pg2    | 172.18.0.12 | Replica | in archive recovery | 1 → 2 | 0   |
| pg3    | 172.18.0.13 | Leader  | running             | 2     |     |

[After 30-50 sec - Streaming Recovery Phase]
| pg1    | 172.18.0.11 | Replica | streaming | 2 | 0 |
| pg2    | 172.18.0.12 | Replica | streaming | 2 | 0 |
| pg3    | 172.18.0.13 | Leader  | running   | 2 |   |
```

### Step 5b: Monitor VIP During Recovery

```bash
# Watch VIP migration in separate terminal (while rejoin is happening)
watch -n 2 'for n in pg1 pg2 pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 2>/dev/null | grep "172.18.0.1[09]" | awk "{print \$2}"
done'
```

**Expected Behavior**:
```
[During Recovery - pg3 still Leader, VIP stays on pg3]
pg1: 172.18.0.11/16
pg2: 172.18.0.12/16
pg3: 172.18.0.13/16
pg3: 172.18.0.10/32    ← VIP remains on pg3 (it's the current leader)
```

### Step 5c: Monitor Replication Catch-up

```bash
# Real-time lag monitoring during recovery
for i in {1..20}; do
  echo "=== Lag Check $i (elapsed: $((i*3)) sec) ==="
  podman exec pg3 psql -U postgres postgres << 'EOF' -t 2>&1 | grep -v "^$"
  SELECT 
    client_addr,
    state,
    ROUND((sent_lsn - replay_lsn) / 1048576.0, 2) AS lag_mb,
    CASE WHEN sent_lsn = replay_lsn THEN '✓ CAUGHT UP' ELSE '⏳ catching up' END AS status
  FROM pg_stat_replication
  ORDER BY client_addr;
EOF
  sleep 3
done
```

**Expected Output Progression**:
```
[Early - High Lag]
172.18.0.11 | streaming | 50.25 MB  | ⏳ catching up
172.18.0.12 | streaming | 48.15 MB  | ⏳ catching up

[Middle - Decreasing Lag]
172.18.0.11 | streaming | 15.50 MB  | ⏳ catching up
172.18.0.12 | streaming | 14.25 MB  | ⏳ catching up

[End - Zero Lag]
172.18.0.11 | streaming |  0.00 MB  | ✓ CAUGHT UP
172.18.0.12 | streaming |  0.00 MB  | ✓ CAUGHT UP
```

### Step 6: Verify All Nodes Operational

```bash
export PGPASSWORD='Pg@Lab2026!'

# Test direct connections
for port in 5433 5434 5435; do
  echo -n "localhost:$port → "
  psql -h localhost -p $port -U postgres postgres -c "SELECT 'OK';" -t 2>&1 | tr -d ' '
  echo
done
```

**Expected Output**:
```
localhost:5433 → OK
localhost:5434 → OK
localhost:5435 → OK
```

### Step 7: Verify Final Replication Lag is Zero

```bash
export PGPASSWORD='Pg@Lab2026!'

# Run on the leader (pg3)
psql -h localhost -p 5435 -U postgres postgres << 'EOF'
SELECT 
  COUNT(*) AS replica_count,
  MAX(ROUND((sent_lsn - replay_lsn) / 1048576.0, 2)) AS max_lag_mb
FROM pg_stat_replication;
EOF
```

**Expected Output** (all replicas caught up):
```
 replica_count | max_lag_mb
---------------+------------
             2 |       0.00
```

---

## 🔙 RESTORE: Switchover pg3 → pg1 (Optional)

### Step 1: Verify Current Leader

```bash
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list | grep Leader
```

**Expected Output**:
```
| pg3    | 172.18.0.13 | Leader  | running   | 2 |           |
```

### Step 2: Execute Switchover (pg3 → pg1)

```bash
podman exec pg3 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader pg3 --candidate pg1 --force
```

**Output**:
```
Switchover scheduled.
```

### Step 3: Wait for Switchover to Complete

```bash
sleep 10
```

### Step 4: Verify pg1 is Now Leader

```bash
podman exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

**Expected Output**:
```
+ Cluster: pg-docker-cls1 (xxx) --+----+-----------+--------------+
| Member | Host        | Role    | State     | TL | Lag in MB | Tags         |
+--------+-------------+---------+-----------+----+-----------+--------------+
| pg1    | 172.18.0.11 | Leader  | running   |  3 |           |              |
| pg2    | 172.18.0.12 | Sync Standby | streaming |  3 |  0  |              |
| pg3    | 172.18.0.13 | Replica | streaming |  3 |  0  | nosync: true |
+--------+-------------+---------+-----------+----+-----------+--------------+
```

### Step 5: Verify VIPs Back to Original Assignments

```bash
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 2>/dev/null | grep "172.18" | awk '{print $2}'
done
```

**Expected Output**:
```
pg1: 172.18.0.11/16
pg1: 172.18.0.10/32        ✓ PRIMARY VIP back to pg1
pg2: 172.18.0.12/16
pg2: 172.18.0.9/32         ✓ REPLICA VIP on pg2 (Sync Standby)
pg3: 172.18.0.13/16
```

---

## ✅ POST-RECOVERY VALIDATION

### Step 1: All PostgreSQL Nodes Operational

```bash
export PGPASSWORD='Pg@Lab2026!'

for port in 5433 5434 5435; do
  echo -n "localhost:$port → "
  psql -h localhost -p $port -U postgres postgres -c "SELECT 'HEALTHY';" -t 2>&1 | tr -d ' '
  echo
done
```

**Expected Output**:
```
localhost:5433 → HEALTHY
localhost:5434 → HEALTHY
localhost:5435 → HEALTHY
```

### Step 2: Patroni REST API Health

```bash
for port in 8011 8012 8013; do
  node=""
  [ "$port" = "8011" ] && node="pg1"
  [ "$port" = "8012" ] && node="pg2"
  [ "$port" = "8013" ] && node="pg3"
  echo -n "$node /patroni: "
  curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:$port/patroni
done
```

**Expected Output**:
```
pg1 /patroni: HTTP 200
pg2 /patroni: HTTP 200
pg3 /patroni: HTTP 200
```

### Step 3: Replication Lag is Zero

```bash
export PGPASSWORD='Pg@Lab2026!'

psql -h localhost -p 5433 -U postgres postgres << 'EOF'
SELECT 
  COUNT(*) as replica_count,
  MIN(ROUND((sent_lsn - replay_lsn) / 1048576.0, 2)) AS min_lag_mb,
  MAX(ROUND((sent_lsn - replay_lsn) / 1048576.0, 2)) AS max_lag_mb
FROM pg_stat_replication;
EOF
```

**Expected Output**:
```
 replica_count | min_lag_mb | max_lag_mb
---------------+------------+------------
             2 |       0.00 |       0.00
```

### Step 4: etcd Cluster Healthy

```bash
podman exec pg1 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health
```

**Expected Output**:
```
http://172.18.0.11:2379 is healthy: successfully committed proposal: took = 10.234ms
http://172.18.0.12:2379 is healthy: successfully committed proposal: took = 10.456ms
http://172.18.0.13:2379 is healthy: successfully committed proposal: took = 10.567ms
```

### Step 5: Verify Data Integrity (DR writes preserved)

```bash
export PGPASSWORD='Pg@Lab2026!'

psql -h localhost -p 5433 -U postgres postgres -c \
  "SELECT COUNT(*) as dr_records FROM dr_test;"
```

**Expected Output**:
```
 dr_records
------------
          2
```

✓ **Data written during DR mode is preserved on pg1 after switchover back!**

---

## 📋 DR Test Validation Matrix

Use this matrix to track the state at each phase of two complete DR test cycles:

### Cycle 1: First Full DR Test

| Phase | Timeline | pg1 Role | pg2 Role | pg3 Role | pg1 State | pg2 State | pg3 State | VIP Location | All Lag = 0 | Notes |
|-------|----------|----------|----------|----------|-----------|-----------|-----------|--------------|-------------|-------|
| Pre-DR | 1 | Leader | Sync Standby | Replica | running | running | running | pg1 | ✓ | Initial state |
| Disaster | 1 | Leader | Sync Standby | Replica | **offline** | **offline** | running | pg1 (old) | N/A | After stop |
| Detected | 1 | offline | offline | Replica | offline | offline | streaming | none | N/A | pg3 not promoted yet |
| Promoted | **2** | offline | offline | **Leader** | offline | offline | running | **pg3** | N/A | After failover --force |
| DR Active | 2 | offline | offline | Leader | offline | offline | running | pg3 | N/A | Accepting writes |
| Recovery Start | 2 | **starting** | **starting** | Leader | starting | starting | running | pg3 | N/A | pg1, pg2 bootup |
| Archive Recovery | **2** | Replica | Replica | Leader | in archive recovery | in archive recovery | running | pg3 | ✓ eventually | Catching up from WAL archive |
| Streaming | 2 | Replica | Replica | Leader | streaming | streaming | running | pg3 | ✓ | All 3 operational |
| Switchover Start | 2 | Replica | Replica | Leader | streaming | streaming | running | pg3 | ✓ | Before switchover command |
| Restored | **3** | **Leader** | **Sync Standby** | **Replica** | running | streaming | streaming | **pg1** | ✓ | Original topology restored |

✓ = Verified, N/A = Not applicable, TL = Timeline

---

### Cycle 2: Repeat DR Test (Optional - To Verify Consistency)

Run the same sequence again to verify:
- Consistent timing between attempts
- Data consistency across cycles
- No degradation in failover/recovery speed
- Repeatability of all observations

Use the same matrix as Cycle 1 to compare results.

---

## 🔧 Troubleshooting: Manual Commands

### Issue: pg3 Fails to Promote to Leader

**Command to diagnose**:
```bash
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list

# Check if Patroni is paused
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list | grep -i pause

# If paused, resume it
podman exec pg3 patronictl -c /etc/patroni/patroni.yml resume
```

**Then retry promotion**:
```bash
podman exec pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force
```

### Issue: VIP Not Migrating to pg3

**Command to diagnose**:
```bash
# Check Keepalived status
podman exec pg3 systemctl status keepalived --no-pager

# Check Keepalived log
podman exec pg3 journalctl -u keepalived --no-pager -n 20
```

**To fix**:
```bash
# Restart Keepalived on pg3
podman exec pg3 systemctl restart keepalived
sleep 5

# Verify VIP is assigned
podman exec pg3 ip addr show eth0 | grep "172.18.0.10"
```

### Issue: pg1/pg2 Not Rejoining After Start

**Command to diagnose**:
```bash
# Check pg1 patroni status
podman exec pg1 systemctl status patroni --no-pager

# Check pg1 patroni logs
podman exec pg1 tail -50 /var/log/patroni/patroni.log

# Check if pg1 can connect to etcd
podman exec pg1 etcdctl --endpoints=http://172.18.0.11:2379 endpoint health
```

**To fix**:
```bash
# Restart Patroni on pg1
podman exec pg1 systemctl restart patroni

# Monitor rejoin
sleep 10
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
```

### Issue: etcd Cluster Unhealthy

**Command to check**:
```bash
podman exec pg3 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health
```

**If etcd is down on any node**:
```bash
# Check etcd service on that node
podman exec pg1 systemctl status etcd --no-pager

# Restart etcd if needed
podman exec pg1 systemctl restart etcd
sleep 5

# Verify cluster again
podman exec pg3 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health
```

### Issue: Promotion Fails with "Already a Leader" Error

**Symptom**: failover command returns error but pg3 is already leader

**Check**:
```bash
# Verify pg3 is actually leader
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list | grep "pg3.*Leader"

# If already leader, error is benign - proceed with writes test
psql -h localhost -p 5435 -U postgres postgres -c "SELECT 'Ready';"
```

### Issue: Timeline Not Advancing During Promotion

**Symptom**: After failover --force, Timeline still shows 1, not 2

**Diagnose**:
```bash
# Check if Patroni is actually managing the promotion
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list --verbose

# Check pg3's control file
podman exec pg3 pg_controldata /var/lib/postgresql/18/main | grep "Database cluster state"

# If state is 'shut down cleanly', Patroni hasn't started pg3 as primary yet
# Wait 5-10 more seconds and check again
sleep 10
podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
```

### Issue: Switchover Hangs or Takes Very Long

**Symptom**: switchover command doesn't return quickly or fails with timeout

**Fix**:
```bash
# Check if any transactions are blocking switchover
podman exec pg3 psql -U postgres postgres -c \
  "SELECT pid, usename, state, query FROM pg_stat_activity WHERE state NOT IN ('idle') AND pid != pg_backend_pid();"

# Kill long-running transactions if needed
# pkill -f pg_sleep  (or similar)

# Retry switchover
podman exec pg3 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader pg3 --candidate pg1 --force
```

### Issue: HAProxy Not Updated After Failover

**Symptom**: HAProxy still shows pg1 as write backend after pg3 promotion

**Check HAProxy status**:
```bash
podman exec pg3 curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" | grep "pg_write"
```

**Fix**:
```bash
# HAProxy should auto-update via health checks (every 5 sec)
# Force refresh by checking again in 10 seconds
sleep 10
podman exec pg3 curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" | grep "pg_write"

# If still not updated, restart HAProxy
podman exec pg3 systemctl restart haproxy
sleep 3
podman exec pg3 curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" | grep "pg_write"
```

---

## 🎯 Understanding Timeline & LSN Changes During DR

### What is Timeline (TL)?

Timeline is a PostgreSQL concept that increments every time:
1. A standby is promoted to leader
2. A failover occurs
3. A new WAL archive begins

**In our DR test**:
- **Pre-DR**: TL = 1 (pg1 is original leader)
- **After pg3 promotion**: TL = 2 (pg3 created new timeline when promoted)
- **After pg3 switches back to pg1**: TL = 3 (pg1 created new timeline after switchover)

### Tracking Timeline During Each Phase

```bash
# Track timeline on each node
for n in pg1 pg2 pg3; do
  port=$([[ "$n" == "pg1" ]] && echo 5433 || [[ "$n" == "pg2" ]] && echo 5434 || echo 5435)
  echo -n "$n: "
  podman exec $n pg_controldata /var/lib/postgresql/18/main 2>/dev/null | grep "Current wal level"
  echo -n "$n timeline: "
  podman exec $n psql -U postgres postgres -c "SELECT timeline_id FROM pg_control_checkpoint();" -t 2>&1 | head -1
done
```

### What is LSN (Log Sequence Number)?

LSN tracks the exact byte position in the WAL (Write-Ahead Log). Key LSN values:

- **sent_lsn**: How far the leader has sent WAL to replicas
- **replay_lsn**: How far the replica has replayed (applied) WAL
- **Lag = sent_lsn - replay_lsn** (in bytes, usually converted to MB)

### Tracking LSN During Recovery

```bash
# Monitor LSN movement (run during recovery phase)
for i in {1..10}; do
  echo "=== LSN Check $i ==="
  podman exec pg3 psql -U postgres postgres << 'EOF' -t 2>&1 | grep -v "^$"
  SELECT 
    'LEADER' AS role,
    pg_current_wal_lsn() AS current_lsn,
    ROUND(EXTRACT(EPOCH FROM now() - pg_postmaster_start_time()), 0)::INT AS uptime_sec
  UNION ALL
  SELECT 
    client_addr::TEXT AS role,
    replay_lsn AS current_lsn,
    ROUND((sent_lsn - replay_lsn) / 1048576.0, 2)::TEXT AS lag_mb
  FROM pg_stat_replication
  ORDER BY role;
EOF
  sleep 5
done
```

### Expected LSN Progression

```
[5 sec after recovery start - Early catch-up]
LEADER: pg_current_wal_lsn() = 0/12345678
172.18.0.11: replay_lsn = 0/10000000, lag = 35.29 MB
172.18.0.12: replay_lsn = 0/09500000, lag = 36.14 MB

[30 sec after - Mid catch-up]
LEADER: pg_current_wal_lsn() = 0/15000000
172.18.0.11: replay_lsn = 0/14800000, lag = 1.95 MB
172.18.0.12: replay_lsn = 0/14700000, lag = 2.93 MB

[60 sec after - Caught up]
LEADER: pg_current_wal_lsn() = 0/15500000
172.18.0.11: replay_lsn = 0/15500000, lag = 0.00 MB
172.18.0.12: replay_lsn = 0/15500000, lag = 0.00 MB
```

---

## 🔄 Replication Slots During DR

### What Happens to Replication Slots During Failover?

Patroni manages replication slots automatically. During pg3 promotion:

1. **Before Promotion**: pg3 was a replica, not consuming slots
2. **During Promotion**: Patroni doesn't create new slots on pg3 (it's now the leader)
3. **After pg1/pg2 rejoin**: They reconnect as replicas, reusing their original slots

### Monitor Slot Status During DR Test

```bash
# Before disaster - verify slots on pg1
podman exec pg1 psql -U postgres postgres -c \
  "SELECT slot_name, slot_type, restart_lsn, restart_lsn IS NULL AS inactive FROM pg_replication_slots ORDER BY slot_name;"
```

**Expected Pre-DR Output**:
```
 slot_name      | slot_type | restart_lsn | inactive
----------------+-----------+-------------+----------
 pg2            | physical  | 0/12345678  | f
 pg3            | physical  | 0/12345678  | f
(2 rows)
```

```bash
# During DR mode - check slots on pg3 (now leader)
podman exec pg3 psql -U postgres postgres -c \
  "SELECT slot_name, slot_type, restart_lsn, restart_lsn IS NULL AS inactive FROM pg_replication_slots ORDER BY slot_name;"
```

**Expected DR Mode Output**:
```
 slot_name      | slot_type | restart_lsn | inactive
----------------+-----------+-------------+----------
(0 rows)
```

Note: No slots on pg3 yet - replicas offline

```bash
# After recovery - slots should re-activate on pg3
podman exec pg3 psql -U postgres postgres -c \
  "SELECT slot_name, slot_type, restart_lsn, restart_lsn IS NULL AS inactive FROM pg_replication_slots ORDER BY slot_name;"
```

**Expected Post-Recovery Output**:
```
 slot_name      | slot_type | restart_lsn | inactive
----------------+-----------+-------------+----------
 pg1            | physical  | 0/12345xxx  | f
 pg2            | physical  | 0/12345xxx  | f
(2 rows)
```

---

## 📊 Complete DR Test Summary

```
NORMAL MODE (Timeline 1):
  podman exec pg1 patronictl -c /etc/patroni/patroni.yml list
  → pg1=Leader, pg2=Sync Standby, pg3=Replica
  → Timeline: 1, Lag: 0.00 MB, Replication Slots: pg2, pg3 (active)

↓ [podman stop pg1 pg2]

DR DETECTED (Still Timeline 1):
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
  → pg1=offline, pg2=offline, pg3=Replica (NOT promoted)
  → Timeline: 1, pg3 cannot accept writes

↓ [podman exec pg3 patronictl ... failover --force]

DR MODE ACTIVE (Timeline 2):
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
  → pg1=offline, pg2=offline, pg3=Leader ✓
  → Timeline: 2 (advanced), pg3 accepts writes, No replication slots

↓ [podman start pg1 pg2 && wait 30-60 sec]

RECOVERY IN PROGRESS (Timeline 2):
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
  → pg1=Replica (archive recovery→streaming), pg2=Replica (same)
  → Timeline: 2, LAG decreasing: 50MB → 10MB → 0.00MB
  → Replication Slots: pg1, pg2 (re-activated)

↓ [podman exec pg3 patronictl ... switchover --leader pg3 --candidate pg1 --force]

RESTORED (Timeline 3):
  podman exec pg1 patronictl -c /etc/patroni/patroni.yml list
  → pg1=Leader, pg2=Sync Standby, pg3=Replica (original topology)
  → Timeline: 3 (advanced), Lag: 0.00 MB
  → Replication Slots: pg2, pg3 (re-created on new leader)
  → Data written during DR preserved ✓
```

---

## ✅ Complete DR Test Verification Checklist

### Before Starting (Pre-DR Baseline)
- [ ] All 3 nodes running (pg1 leader, pg2 standby, pg3 replica)
- [ ] Cluster topology correct (pg1 Leader, pg2 Sync Standby, pg3 Replica nosync)
- [ ] VIP on pg1 (172.18.0.10)
- [ ] All Patroni health endpoints returning correct HTTP codes
- [ ] All PostgreSQL connections responding
- [ ] HAProxy write pool showing pg1 as UP
- [ ] Replication lag = 0.00 MB
- [ ] Replication slots active for pg2 and pg3
- [ ] etcd cluster healthy (all 3 members)
- [ ] Baseline data snapshot captured

### Cycle 1: Full DR Test (Repeat to verify consistency)

#### Disaster & Promotion Phase
- [ ] pg1 and pg2 stopped successfully
- [ ] Verify pg1/pg2 offline in 10 seconds
- [ ] pg3 still Replica after stop
- [ ] etcd still accessible from pg3
- [ ] Failover command issued: `patronictl failover --force`
- [ ] pg3 promoted to Leader within 5 seconds
- [ ] Timeline advanced from 1 to 2
- [ ] VIP migrated to pg3 (172.18.0.10)
- [ ] pg3 is NOT in recovery (pg_is_in_recovery() = false)
- [ ] HAProxy write pool now shows pg3 as UP

#### DR Mode Active Phase
- [ ] Create test table and insert data successfully
- [ ] Data query returns records
- [ ] pg3 /primary endpoint returns HTTP 200
- [ ] pg3 /replica endpoint returns HTTP 503 (no replicas)
- [ ] Patroni health shows only pg3 as member

#### Recovery & Rejoin Phase
- [ ] pg1 and pg2 started successfully
- [ ] Containers running within 20 seconds
- [ ] pg1 and pg2 detected by Patroni (not offline anymore)
- [ ] Archive recovery phase observed (10-30 seconds)
- [ ] Streaming replication phase observed
- [ ] Timeline on pg1/pg2 updated to 2
- [ ] VIP remains on pg3 (still the leader)
- [ ] Replication lag decreases over time
- [ ] All replicas reach 0.00 MB lag
- [ ] All 3 nodes operational (direct PostgreSQL connections work)

#### Switchover & Restore Phase
- [ ] pg3 verified as current leader before switchover
- [ ] Switchover command executed: `patronictl switchover --leader pg3 --candidate pg1 --force`
- [ ] pg1 promoted to Leader within 10 seconds
- [ ] Timeline advanced to 3
- [ ] pg2 role changed to Sync Standby
- [ ] pg3 role changed back to Replica
- [ ] VIP migrated to pg1 (172.18.0.10)
- [ ] Original topology restored (pg1=Leader, pg2=Standby, pg3=Replica)

#### Post-Recovery Validation (Cycle 1)
- [ ] All 3 PostgreSQL nodes operational
- [ ] All Patroni health endpoints returning correct codes
- [ ] Replication lag = 0.00 MB on both replicas
- [ ] All replication slots active
- [ ] etcd cluster healthy
- [ ] DR test data preserved (dr_test table has 2 records)
- [ ] Timeline progression correct (1 → 2 → 3)
- [ ] Total cycle time recorded: ____ seconds

### Cycle 2: Repeat Full Test (Consistency Verification)

Repeat the same checklist as Cycle 1, comparing:
- [ ] Cycle 1 and Cycle 2 timings are consistent (within ±5 seconds)
- [ ] All node roles transition in same order
- [ ] LAG progression follows same pattern
- [ ] VIP migrations occur at same intervals
- [ ] Data integrity consistent across cycles
- [ ] No error messages in any logs
- [ ] Total cycle time recorded: ____ seconds

**Comparison Result**: Cycle 1 = ____ sec, Cycle 2 = ____ sec (Δ = ____ sec)
- If Δ < 5 sec: ✓ CONSISTENT
- If Δ > 5 sec: ⚠️ VARIABLE (investigate cause)
