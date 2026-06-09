# DR Switchover Guide

## Topology Reference

| Cluster | Members | Role | Container IP | VIP |
|---------|---------|------|-------------|-----|
| **Primary** (before switchover) | docpg-cls1-pg1 | Leader | 172.18.0.11 | 172.18.0.10 (write) |
| | docpg-cls1-pg2 | Sync Replica | 172.18.0.12 | 172.18.0.9 (read) |
| | docpg-cls1-pg3 | Async Replica | 172.18.0.13 | — |
| **Standby** (before switchover) | docpg-cls1-pg4 | Standby Leader | 172.18.0.14 | — |

The physical replication slot **`standby_cluster_slot`** on the primary cluster leader is provisioned
and maintained automatically by Patroni (configured in `hosts.yml` via
`patroni_standby_cluster_slot_name`). **No manual slot creation or deletion is needed at any
point during this procedure.**

---

## Planned DR Switchover — Step-by-Step Runbook

> This procedure performs a **planned, zero-data-loss switchover** of the active primary from
> the original primary cluster (pg1/pg2/pg3) to the standby cluster (pg4), then reconfigures
> the original primary cluster as the new standby.
>
> All commands run via `docker exec` — no SSH required. `psql` authenticates using
> `/root/.pgpass` inside each container.

---

### Step 0 - Check current `standby_cluster` config on both primary & standby cluster side

```bash
patronictl -c /etc/patroni/patroni.yml show-config docpg-cls1 | grep -A5 standby_cluster
```

> Output on Primary Cluster (docpg-cls1-pg1) -
```
ajaydwivedi@Ajays-MacBook-Pro Office % docker exec -it docpg-cls1-pg1 bash
root@docpg-cls1-pg1:/# patronictl -c /etc/patroni/patroni.yml show-config docpg-cls1 | grep -A5 standby_cluster
  standby_cluster_slot:
    type: physical
synchronous_mode: true
synchronous_mode_strict: false
synchronous_node_count: 1
ttl: 30
root@docpg-cls1-pg1:/# 
root@docpg-cls1-pg1:/# patronictl list
+ Cluster: docpg-cls1 (7649402051775700970) --+-----------+----+-----------+------------------+
| Member         | Host        | Role         | State     | TL | Lag in MB | Tags             |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg1 | 172.18.0.11 | Leader       | running   |  2 |           |                  |
| docpg-cls1-pg2 | 172.18.0.12 | Sync Standby | streaming |  2 |         0 |                  |
| docpg-cls1-pg3 | 172.18.0.13 | Replica      | streaming |  2 |         0 | nofailover: true |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
root@docpg-cls1-pg1:/# 
root@docpg-cls1-pg1:/# 
```

> Output on Standby Cluster (docpg-cls1-pg4) -
```
ajaydwivedi@Ajays-MacBook-Pro Office % docker exec -it docpg-cls1-pg4 bash
root@docpg-cls1-pg4:/# patronictl -c /etc/patroni/patroni.yml show-config docpg-cls1 | grep -A5 standby_cluster
standby_cluster:
  host: 172.18.0.10
  port: 5432
  primary_slot_name: standby_cluster_slot
synchronous_mode: true
synchronous_mode_strict: false
synchronous_node_count: 1
ttl: 30

root@docpg-cls1-pg4:/# 
root@docpg-cls1-pg4:/# 
root@docpg-cls1-pg4:/# patronictl list
+ Cluster: docpg-cls1 (7649402051775700970) ----+-----------+----+-----------+
| Member         | Host        | Role           | State     | TL | Lag in MB |
+----------------+-------------+----------------+-----------+----+-----------+
| docpg-cls1-pg4 | 172.18.0.14 | Standby Leader | streaming |  2 |           |
+----------------+-------------+----------------+-----------+----+-----------+
root@docpg-cls1-pg4:/# 
```

### Step 1 — Put Primary Cluster in Maintenance Mode

Pausing Patroni prevents automatic leader elections while you drain connections and confirm
replication lag. Maintenance mode does **not** stop PostgreSQL or replication.

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml pause --wait docpg-cls1
```

Verify all members show **paused**:

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml list docpg-cls1
# All members should have "(paused)" in their State column
```

---

### Step 2 — Stop New Connections to the Primary Cluster Leader

Block new application sessions before beginning the drain. Superuser (`postgres`) and
replication (`replicator`) logins remain unaffected.

```bash
# Set connection limit to 0 on each application database.
# Adjust the database list to match your environment.
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres -c "
  ALTER DATABASE dba CONNECTION LIMIT 0;
"

# Confirm the limit is in place
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres -c "
  SELECT datname, datconnlimit
  FROM pg_database
  WHERE datname NOT IN ('template0', 'template1', 'postgres');
"
```

---

### Step 3 — Terminate Existing Non-Superuser Connections

Force-close any open application sessions that were established before the connection limit
took effect.

```bash
docker exec docpg-cls1-pg1 psql -h docpg-cls1-pg1 -U postgres << "EOF"
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE datname NOT IN ('template0', 'template1', 'postgres')
  AND usename NOT IN ('postgres', 'replicator')
  AND pid <> pg_backend_pid();
EOF
```

Confirm no remaining application connections:

```bash
docker exec docpg-cls1-pg1 psql -h docpg-cls1-pg1 -U postgres -c "
SELECT pid, usename, datname, application_name, state, query_start
FROM pg_stat_activity
WHERE usename NOT IN ('postgres', 'replicator')
  AND pid <> pg_backend_pid()
ORDER BY query_start;
"
# ✅ Expected: 0 rows
```

---

### Step 4 — Validate Replication Lag

**Do not proceed to Step 5 until both checks confirm lag = 0.**

**From the primary leader (docpg-cls1-pg1):**

```bash
docker exec docpg-cls1-pg1 psql -h docpg-cls1-pg2 -U postgres postgres -c "
SELECT
  application_name,
  state,
  sync_state,
  pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)   AS sent_lag_bytes,
  pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn)  AS write_lag_bytes,
  pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)  AS flush_lag_bytes,
  pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes,
  write_lag, flush_lag, replay_lag
FROM pg_stat_replication
WHERE application_name = 'docpg-cls1-pg4';
"
# ✅ flush_lag_bytes and replay_lag_bytes must be 0
```

**From the standby leader (docpg-cls1-pg4):**

```bash
docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres postgres -c "
SELECT
  status,
  sender_host,
  pg_last_wal_receive_lsn()                                              AS received_lsn,
  pg_last_wal_replay_lsn()                                               AS replayed_lsn,
  pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())  AS apply_lag_bytes,
  EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int     AS replay_lag_seconds
FROM pg_stat_wal_receiver;
"
# ✅ apply_lag_bytes must be 0, status must be 'streaming'
```

**Quick combined check (both hops in one shot):**

```bash
echo "=== Primary side (pg1 → pg4) ===" && \
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres postgres -At -c "
  SELECT application_name||E'\tflush_lag_MB='||
         round(pg_wal_lsn_diff(pg_current_wal_lsn(),flush_lsn)/1024.0/1024,2)||
         E'\treplay_lag='||coalesce(replay_lag::text,'0')
  FROM pg_stat_replication WHERE application_name='docpg-cls1-pg4';" && \
echo "=== Standby side (pg4 local apply) ===" && \
docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres postgres -At -c "
  SELECT status||E'\tapply_lag_MB='||
         round(pg_wal_lsn_diff(pg_last_wal_receive_lsn(),pg_last_wal_replay_lsn())/1024.0/1024,2)||
         E'\treplay_age_sec='||coalesce(extract(epoch from (now()-pg_last_xact_replay_timestamp()))::int::text,'0')
  FROM pg_stat_wal_receiver;"
```

---

### Step 5 — Stop Primary Cluster (Once Lag = 0)

Stop Patroni (and PostgreSQL) on all primary cluster members. Stop replicas before the leader
to avoid unnecessary failover traffic.

```bash
# Stop replicas first
docker exec docpg-cls1-pg2 systemctl stop patroni
docker exec docpg-cls1-pg3 systemctl stop patroni

# Stop the leader last
docker exec docpg-cls1-pg1 systemctl stop patroni
```

Optionally stop the containers to prevent accidental restarts:

```bash
docker stop docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3
```

Verify all three are down:

```bash
docker ps --filter name=docpg-cls1-pg --format "table {{.Names}}\t{{.Status}}"
# ✅ pg1, pg2, pg3 should be absent or show Exited
```

---

### Step 6 — Promote Standby Cluster to Primary

Remove the `standby_cluster` block from the DCS configuration. Patroni on `docpg-cls1-pg4`
detects this change and promotes PostgreSQL from a streaming standby to a normal read-write
primary. At the same time, provision a permanent physical slot (`standby_cluster_slot`) so that the old primary cluster can securely stream from pg4 when it returns as the new standby.

```bash
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "standby_cluster=null" \
  --set "slots.standby_cluster_slot.type=physical"
```

Restart Patroni on pg4 to ensure the promotion is applied immediately:

```bash
docker exec docpg-cls1-pg4 systemctl restart patroni
```

Wait for pg4 to become the primary leader:

```bash
until docker exec docpg-cls1-pg4 \
        curl -sf http://172.18.0.14:8008/primary > /dev/null 2>&1; do
  echo "Waiting for pg4 to become primary..."; sleep 3
done
echo "✅ pg4 is now primary"
```

Confirm promotion and capture the current timeline:

```bash
docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres -c \
  "SELECT pg_is_in_recovery(), timeline_id FROM pg_control_checkpoint();"
# ✅ pg_is_in_recovery = f, timeline_id = (previous_timeline + 1)
```

```bash
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml list docpg-cls1
# ✅ docpg-cls1-pg4 role = Leader
```

---

### Step 7 — Restart New Primary Members 3 Times to Advance Timeline

Advancing the PostgreSQL timeline on pg4 ensures the old primary cluster members (pg1/pg2/pg3)
will unambiguously recognise pg4 as the upstream when they return as the new standby cluster.
Patroni performs a clean stop-and-start of PostgreSQL on each cycle.

> Before each restart, wait for pg4 to be healthy (Leader, `pg_is_in_recovery = f`).
> If there are replicas in the new primary cluster, also wait for them to return to
> `streaming` state before triggering the next restart.

**Restart 1 of 3:**

```bash
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  restart docpg-cls1 docpg-cls1-pg4 --force

until docker exec docpg-cls1-pg4 \
        curl -sf http://172.18.0.14:8008/primary > /dev/null 2>&1; do
  echo "Waiting..."; sleep 3
done && echo "✅ pg4 healthy after restart 1"

docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres -At -c \
  "SELECT timeline_id FROM pg_control_checkpoint();"
```

**Restart 2 of 3:**

```bash
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  restart docpg-cls1 docpg-cls1-pg4 --force

until docker exec docpg-cls1-pg4 \
        curl -sf http://172.18.0.14:8008/primary > /dev/null 2>&1; do
  echo "Waiting..."; sleep 3
done && echo "✅ pg4 healthy after restart 2"

docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres -At -c \
  "SELECT timeline_id FROM pg_control_checkpoint();"
```

**Restart 3 of 3:**

```bash
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  restart docpg-cls1 docpg-cls1-pg4 --force

until docker exec docpg-cls1-pg4 \
        curl -sf http://172.18.0.14:8008/primary > /dev/null 2>&1; do
  echo "Waiting..."; sleep 3
done && echo "✅ pg4 healthy after restart 3"

docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres -At -c \
  "SELECT timeline_id FROM pg_control_checkpoint();"
```

Final new-primary state check:

```bash
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml list docpg-cls1
# ✅ docpg-cls1-pg4 — Leader — running — TL advanced
```

---

### Step 8 — Bring Old Primary Cluster Back Up

Start the old primary cluster containers and Patroni. Because the old cluster's etcd DCS still
holds the previous leader state and has **no `standby_cluster` config yet**, Patroni will elect
a leader among pg1/pg2/pg3. This is expected — the cluster comes up momentarily as a standalone
(non-standby) primary. **Do not allow application writes to it.** The standby config is applied
in Step 9.

```bash
# Start containers if they were stopped in Step 5
docker start docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3

# Start Patroni on all three members
docker exec docpg-cls1-pg1 systemctl start patroni
docker exec docpg-cls1-pg2 systemctl start patroni
docker exec docpg-cls1-pg3 systemctl start patroni
```

Wait for patroni service to start, and patronictl command to return member list

Scenario 01: In Real Disaster, the old primary cluster members come online, and start cluster with a "Leader"
Scenario 02: In DR Drill, the old primary members would NOT come online. Would be in STOPPED state due to "maintenance" mode config before DR promotion.

> **⚠️ Do not allow application traffic to this cluster.**
> It holds a stale copy of data and will be demoted to standby in the next steps.

---

### Step 9 — Add `standby_cluster` Config to Old Primary Cluster

Write the `standby_cluster` block into the old cluster's DCS, pointing it at pg4. Patroni
propagates this to all members automatically.

The old primary cluster will connect to the new primary (pg4) and stream using the **`standby_cluster_slot`** (which we permanently provisioned in pg4's DCS back in Step 6).

```bash
# Run from any member of the old primary cluster.
# The change is stored in etcd and applies cluster-wide.
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "standby_cluster.host=docpg-cls1-pg4" \
  --set "standby_cluster.port=5432" \
  --set "standby_cluster.primary_slot_name=standby_cluster_slot"
```

Verify the config was written to DCS:

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml \
  show-config docpg-cls1 | grep -A5 standby_cluster
# ✅ host: 172.18.0.14, port: 5432, primary_slot_name: standby_cluster_slot
```

---

### Step 10 — Remove Old Primary Cluster from Maintenance Mode

Resume Patroni on the old cluster so it can carry out the demotion in Step 11.

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml resume --wait docpg-cls1
```

Verify maintenance mode is lifted:

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml list docpg-cls1
# ✅ "(paused)" should no longer appear
```

---

### Step 11 — Restart Old Cluster Members to Demote to Standby

Restarting each member with the `standby_cluster` config active causes Patroni to stop
PostgreSQL, align the WAL position against pg4 (via `pg_rewind` or `pg_basebackup` if
needed), and restart as a streaming standby.

Restart the **intended standby leader first** (the node that was elected leader in Step 8),
then the remaining replicas:

```bash
# Restart the standby leader candidate first
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml \
  restart docpg-cls1 docpg-cls1-pg1 --force

# Wait for pg1 to reach standby-leader state
until docker exec docpg-cls1-pg1 \
        curl -sf http://172.18.0.11:8008/standby-leader > /dev/null 2>&1; do
  echo "Waiting for pg1 to become standby leader..."; sleep 3
done
echo "✅ pg1 is standby leader"

# Restart remaining replicas
docker exec docpg-cls1-pg2 \
  patronictl -c /etc/patroni/patroni.yml \
  restart docpg-cls1 docpg-cls1-pg2 --force

docker exec docpg-cls1-pg3 \
  patronictl -c /etc/patroni/patroni.yml \
  restart docpg-cls1 docpg-cls1-pg3 --force
```

---

### Step 12 — Verify New Standby Cluster

**On the new standby cluster (old primary):**

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml list docpg-cls1

# ✅ Expected:
# | Member           | Host        | Role           | State     | TL | Lag in MB |
# | docpg-cls1-pg1   | 172.18.0.11 | Standby Leader | streaming | NN |     0     |
# | docpg-cls1-pg2   | 172.18.0.12 | Replica        | streaming | NN |     0     |
# | docpg-cls1-pg3   | 172.18.0.13 | Replica        | streaming | NN |     0     |
```

Verify pg1 is in recovery (standby mode), not a primary:

```bash
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres -c \
  "SELECT pg_is_in_recovery(), timeline_id FROM pg_control_checkpoint();"
# ✅ pg_is_in_recovery = t
```

**On the new primary cluster (pg4):**

```bash
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml list docpg-cls1

# ✅ Expected:
# | Member           | Host        | Role   | State   | TL | Lag in MB |
# | docpg-cls1-pg4   | 172.18.0.14 | Leader | running | NN |     0     |
```

Verify `standby_cluster_slot` is active on pg4 (provisioned in DCS in Step 6, and activated when pg1 connected):

```bash
docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres -c "
SELECT slot_name, slot_type, active, active_pid, restart_lsn
FROM pg_replication_slots
WHERE slot_name = 'standby_cluster_slot';
"
# ✅ active = t, active_pid is non-null
```

Verify replication lag from pg4 to the standby leader (pg1):

```bash
docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres -c "
SELECT
  application_name,
  state,
  sync_state,
  pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) AS flush_lag_bytes,
  replay_lag
FROM pg_stat_replication
WHERE application_name = 'docpg-cls1-pg1';
"
# ✅ state = streaming, flush_lag_bytes approaching 0
```

---

## Appendix — Checking Replication Lag Between Primary and Standby Cluster

In this topology — primary cluster `docpg-cls1-pg1/pg2/pg3` (Region A) and cascading async standby `docpg-cls1-pg4` (Region B) — replication lag must be measured at **two hops**, because docpg-cls1-pg4 streams from the primary cluster's leader via `standby_cluster`, not as a member of the primary Patroni cluster. `patronictl list` on docpg-cls1-pg1 will NOT show docpg-cls1-pg4 (it belongs to its own cluster DCS).

All `docker exec` commands below run psql as `root` using the container's `/root/.pgpass` — no `PGPASSWORD` env var needed.

### 1. From the Primary leader (docpg-cls1-pg1) — `pg_stat_replication`

Authoritative view. docpg-cls1-pg4 appears as a streaming client of docpg-cls1-pg1.

```bash
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -p 5432 -U postgres postgres -c "
SELECT
  application_name,
  client_addr,
  state,
  sync_state,
  pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)   AS sent_lag_bytes,
  pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn)  AS write_lag_bytes,
  pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)  AS flush_lag_bytes,
  pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes,
  write_lag, flush_lag, replay_lag
FROM pg_stat_replication
WHERE application_name = 'docpg-cls1-pg4';"
```

What to read:
- `flush_lag_bytes` / `replay_lag_bytes` — how far docpg-cls1-pg4 is behind in **bytes** of WAL.
- `write_lag` / `flush_lag` / `replay_lag` — how far behind in **time** (interval).
- `sync_state = async` is expected for cascading DR.

Alert on `flush_lag_bytes > 100 MB` or `replay_lag > '60 seconds'`.

### 2. From the standby cluster leader (docpg-cls1-pg4) — receiver + replay LSNs

Confirms what docpg-cls1-pg4 has actually received and replayed:

```bash
docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -p 5432 -U postgres postgres -c "
SELECT
  status,
  sender_host,
  pg_last_wal_receive_lsn()                                                  AS received_lsn,
  pg_last_wal_replay_lsn()                                                   AS replayed_lsn,
  pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())       AS apply_lag_bytes,
  EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int         AS replay_lag_seconds
FROM pg_stat_wal_receiver;"
```

What to read:
- `apply_lag_bytes` — WAL **received but not yet replayed** on docpg-cls1-pg4 (local apply backlog).
- `replay_lag_seconds` — clock skew of last committed tx vs now; useful when docpg-cls1-pg1 is idle (no traffic → still 0 lag bytes but `replay_lag_seconds` grows).
- `status = streaming` confirms the link is up.

> Tip: when the primary is idle, `pg_stat_replication` lags can read `NULL`/0 even though docpg-cls1-pg4 hasn't received recent activity. Combine **(1)** and **(2)**.

### 3. From patronictl on the standby cluster

docpg-cls1-pg4 runs its own Patroni cluster, so query it locally:

```bash
docker exec docpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
# | Member           | Host        | Role            | State     | TL | Lag in MB |
# | docpg-cls1-pg4   | 172.18.0.14 | Standby Leader  | streaming | NN | <X> MB    |
```

The `Lag in MB` column = bytes behind the upstream primary (docpg-cls1-pg1). Quickest sanity check, granular to MB.

### 4. Patroni REST API (good for monitoring/scraping)

```bash
# Primary leader's view of replicas (won't include docpg-cls1-pg4 unless queried directly)
curl -s http://172.18.0.11:8008/cluster | jq '.members[] | {name, role, state, lag}'

# Standby cluster leader's own view
curl -s http://172.18.0.14:8008/cluster | jq '.members[] | {name, role, state, lag}'

# docpg-cls1-pg4 health endpoint returns xlog info
curl -s http://172.18.0.14:8008/patroni | jq '.xlog'
# {
#   "received_location": ...,
#   "replayed_location": ...,
#   "replayed_timestamp": ...,
#   "paused": false
# }
```

### Recommended single-command "DR lag" check

Use this before any failover drill — it gives you both hops in one shot:

```bash
echo "=== Primary side (docpg-cls1-pg1 → docpg-cls1-pg4) ==="
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres postgres -At -c "
SELECT application_name||E'\t'||state||E'\t'||sync_state
       ||E'\tflush_lag_MB='||round(pg_wal_lsn_diff(pg_current_wal_lsn(),flush_lsn)/1024.0/1024,2)
       ||E'\treplay_lag='||coalesce(replay_lag::text,'0')
  FROM pg_stat_replication WHERE application_name='docpg-cls1-pg4';"

echo "=== Standby side (docpg-cls1-pg4 local apply) ==="
docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres postgres -At -c "
SELECT status||E'\tapply_lag_MB='||round(pg_wal_lsn_diff(pg_last_wal_receive_lsn(),pg_last_wal_replay_lsn())/1024.0/1024,2)
       ||E'\treplay_age_sec='||coalesce(extract(epoch from (now()-pg_last_xact_replay_timestamp()))::int::text,'0')
  FROM pg_stat_wal_receiver;"
```

### Thresholds (rule of thumb)

| Metric | Healthy | Warn | Critical |
|---|---|---|---|
| `flush_lag_bytes` (docpg-cls1-pg1 → docpg-cls1-pg4) | < 16 MB | 16–100 MB | > 100 MB |
| `replay_lag` (time) | < 5 s | 5–60 s | > 60 s |
| `apply_lag_bytes` on docpg-cls1-pg4 | < 8 MB | 8–50 MB | > 50 MB |
| Patroni `Lag in MB` | 0 MB | 1–50 MB | > 50 MB |
