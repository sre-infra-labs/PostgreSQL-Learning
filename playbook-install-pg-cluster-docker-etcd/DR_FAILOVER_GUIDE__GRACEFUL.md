# DR Switchover Guide - Graceful Switchover

In graceful switchover, DBA coordinates with application teams to perform a graceful switchover.
DBA controls the unavailability of primary cluster nodes, and application teams perform a graceful
shutdown of their respective applications.

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
cd ~/GitHub/PostgreSQL-Learning/playbook-install-pg-cluster-docker-etcd

### Step 0 - Check current `standby_cluster` config on both primary & standby cluster side

```bash
echo "=== Primary Cluster (docpg-cls1-pg1) ==="
docker exec docpg-cls1-pg1 \
    patronictl -c /etc/patroni/patroni.yml show-config docpg-cls1 | grep -A5 standby_cluster
echo "=== Standby Cluster (docpg-cls1-pg4) ==="
docker exec docpg-cls1-pg4 \
    patronictl -c /etc/patroni/patroni.yml show-config docpg-cls1 | grep -A5 standby_cluster

echo "=== Primary Cluster (docpg-cls1-pg1) ==="
docker exec docpg-cls1-pg1 \
    patronictl -c /etc/patroni/patroni.yml list
echo "=== Standby Cluster (docpg-cls1-pg4) ==="
docker exec docpg-cls1-pg4 \
    patronictl -c /etc/patroni/patroni.yml list
```

> Output
```
|------------$ echo "=== Primary Cluster (docpg-cls1-pg1) ==="
docker exec docpg-cls1-pg1 \
    patronictl -c /etc/patroni/patroni.yml show-config docpg-cls1 | grep -A5 standby_cluster
echo "=== Standby Cluster (docpg-cls1-pg4) ==="
docker exec docpg-cls1-pg4 \
    patronictl -c /etc/patroni/patroni.yml show-config docpg-cls1 | grep -A5 standby_cluster

=== Primary Cluster (docpg-cls1-pg1) ===
  standby_cluster_slot:
    type: physical
synchronous_mode: true
synchronous_mode_strict: false
synchronous_node_count: 1
ttl: 30
=== Standby Cluster (docpg-cls1-pg4) ===
standby_cluster:
  host: 172.18.0.10
  port: 5432
  primary_slot_name: standby_cluster_slot
synchronous_mode: true
synchronous_mode_strict: false
synchronous_node_count: 1
ttl: 30


|------------$ echo "=== Primary Cluster (docpg-cls1-pg1) ==="
docker exec docpg-cls1-pg1 \
    patronictl -c /etc/patroni/patroni.yml list
echo "=== Standby Cluster (docpg-cls1-pg4) ==="
docker exec docpg-cls1-pg4 \
    patronictl -c /etc/patroni/patroni.yml list

=== Primary Cluster (docpg-cls1-pg1) ===
+ Cluster: docpg-cls1 (7649631878658509655) --+-----------+----+-----------+------------------+
| Member         | Host        | Role         | State     | TL | Lag in MB | Tags             |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg1 | 172.18.0.11 | Leader       | running   |  2 |           |                  |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg2 | 172.18.0.12 | Sync Standby | streaming |  2 |         0 |                  |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg3 | 172.18.0.13 | Replica      | streaming |  2 |         0 | nofailover: true |
|                |             |              |           |    |           | nosync: true     |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
=== Standby Cluster (docpg-cls1-pg4) ===
+ Cluster: docpg-cls1 (7649631878658509655) ----+-----------+----+-----------+
| Member         | Host        | Role           | State     | TL | Lag in MB |
+----------------+-------------+----------------+-----------+----+-----------+
| docpg-cls1-pg4 | 172.18.0.14 | Standby Leader | streaming |  2 |           |
+----------------+-------------+----------------+-----------+----+-----------+
```


### Step 1 - Create test tables for data less testing
```bash
docker exec -it docpg-cls1-pg1 bash
patronictl list

-- Run on leader node
psql -h localhost -U postgres -d dba << 'EOF'
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE IF NOT EXISTS public.multi_dc_failover_test
(
    create_datetime timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    action          citext NOT NULL
);

INSERT INTO public.multi_dc_failover_test (action)
VALUES ('Initial state: pg1 is primary'),
      ('Initial state: pg4 is standby');

SELECT * FROM public.multi_dc_failover_test ORDER BY create_datetime DESC;

EOF

docker exec docpg-cls1-pg1 \
    psql -h localhost -U postgres -d dba -c "SELECT * FROM public.multi_dc_failover_test ORDER BY create_datetime DESC;"
```

### Step 2 — Put Primary Cluster in Maintenance Mode

Pausing Patroni prevents automatic leader elections while you drain connections and confirm
replication lag. Maintenance mode does **not** stop PostgreSQL or replication.

```bash
echo "=== Primary Cluster (docpg-cls1-pg1) ==="
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml pause --wait docpg-cls1

echo "=== Primary Cluster (docpg-cls1-pg1) ==="
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml list
```

> Output
```
|------------$ docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml pause --wait docpg-cls1

'pause' request sent, waiting until it is recognized by all nodes
Success: cluster management is paused

|------------$ 
|------------$ echo "=== Primary Cluster (docpg-cls1-pg1) ==="
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml list

=== Primary Cluster (docpg-cls1-pg1) ===
+ Cluster: docpg-cls1 (7649631878658509655) --+-----------+----+-----------+------------------+
| Member         | Host        | Role         | State     | TL | Lag in MB | Tags             |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg1 | 172.18.0.11 | Leader       | running   |  2 |           |                  |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg2 | 172.18.0.12 | Sync Standby | streaming |  2 |         0 |                  |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg3 | 172.18.0.13 | Replica      | streaming |  2 |         0 | nofailover: true |
|                |             |              |           |    |           | nosync: true     |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
 Maintenance mode: on
```


---

### Step 3 — During DR Drill Only - Stop New Connections to the Primary Cluster Leader

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

### Step 4 — During DR Drill Only - Terminate Existing Non-Superuser Connections on Primary Cluster Leader

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

### Step 5 — During DR Drill Only - Validate Replication Lag

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

### Step 6 — Stop Primary Cluster (Once Lag = 0)

Stop Patroni (and PostgreSQL) on all primary cluster members. Stop replicas before the leader
to avoid unnecessary failover traffic.

```bash
# Stop replicas first
docker exec docpg-cls1-pg2 systemctl stop patroni
docker exec docpg-cls1-pg2 sudo -u postgres /usr/lib/postgresql/18/bin/pg_ctl stop -D /var/lib/postgresql/18/main -m fast

docker exec docpg-cls1-pg3 systemctl stop patroni
docker exec docpg-cls1-pg3 sudo -u postgres /usr/lib/postgresql/18/bin/pg_ctl stop -D /var/lib/postgresql/18/main -m fast

# Stop the leader last
docker exec docpg-cls1-pg1 systemctl stop patroni
docker exec docpg-cls1-pg1 sudo -u postgres /usr/lib/postgresql/18/bin/pg_ctl stop -D /var/lib/postgresql/18/main -m fast
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

Post this, the standby cluster leader will go into `in archive recovery` state.

```bash
root@docpg-cls1-pg4:/# # *************** WHEN PRIMARY CLUSTER IS ONLINE ********************************
root@docpg-cls1-pg4:/# patronictl list
+ Cluster: docpg-cls1 (7649402051775700970) ----+-----------+----+-----------+
| Member         | Host        | Role           | State     | TL | Lag in MB |
+----------------+-------------+----------------+-----------+----+-----------+
| docpg-cls1-pg4 | 172.18.0.14 | Standby Leader | streaming |  2 |           |
+----------------+-------------+----------------+-----------+----+-----------+
root@docpg-cls1-pg4:/# 


root@docpg-cls1-pg4:/# # *************** WHEN PRIMARY CLUSTER IS OFFLINE ********************************
root@docpg-cls1-pg4:/# patronictl list
+ Cluster: docpg-cls1 (7649402051775700970) ----+---------------------+----+-----------+
| Member         | Host        | Role           | State               | TL | Lag in MB |
+----------------+-------------+----------------+---------------------+----+-----------+
| docpg-cls1-pg4 | 172.18.0.14 | Standby Leader | in archive recovery |  2 |           |
+----------------+-------------+----------------+---------------------+----+-----------+
root@docpg-cls1-pg4:/# 
```

---

### Step 7 — Promote Standby Cluster to Primary

Remove the `standby_cluster` block from the DCS configuration. 
Patroni on `docpg-cls1-pg4` detects this change and promotes PostgreSQL from a streaming standby to a normal read-write primary.
At the same time, provision a permanent physical slot (`standby_cluster_slot`) so that the old primary cluster can securely stream from pg4 when it returns as the new standby.

```bash
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "standby_cluster=null" \
  --set "slots.standby_cluster_slot.type=physical"

echo "=== Check new primary cluster health (docpg-cls1-pg4) ==="
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml list
```

> Output -
```
root@docpg-cls1-pg4:/#
|------------$ docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "standby_cluster=null" \
  --set "slots.standby_cluster_slot.type=physical"
--- 
+++ 
@@ -75,10 +75,9 @@
   use_pg_rewind: true
   use_slots: true
 retry_timeout: 10
-standby_cluster:
-  host: 172.18.0.10
-  port: 5432
-  primary_slot_name: standby_cluster_slot
+slots:
+  standby_cluster_slot:
+    type: physical
 synchronous_mode: true
 synchronous_mode_strict: false
 synchronous_node_count: 1
Configuration changed
root@docpg-cls1-pg4:/# 
```

Patroni cluster should automatically get promoted with above config change.
Now, we should see a member with "Leader" role.

> Output -
```
|------------$ docker exec docpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
+ Cluster: docpg-cls1 (7649631878658509655) ------+----+-----------+
| Member         | Host        | Role   | State   | TL | Lag in MB |
+----------------+-------------+--------+---------+----+-----------+
| docpg-cls1-pg4 | 172.18.0.14 | Leader | running |  3 |           |
+----------------+-------------+--------+---------+----+--------
root@docpg-cls1-pg4:/# 
```

> [! IMPORTANT]
> If old primary cluster went down without `maintenance` mode, then once it comes up, it would take one timeline above the new primary cluster causing `SPLIT BRAIN`.

---

### Step 8 - Make data entries on new primary cluster during DR situation
```bash
psql -h localhost -U postgres -d dba << 'EOF'
INSERT INTO public.multi_dc_failover_test (action)
VALUES ('During DR situation: Failover. pg4 is promoted to primary');

INSERT INTO public.multi_dc_failover_test (action)
VALUES ('During DR situation: Failover. This is written from DR site');

INSERT INTO public.multi_dc_failover_test (action)
VALUES ('During DR situation: Failover. pg1 site is down.');

SELECT * FROM public.multi_dc_failover_test ORDER BY create_datetime DESC limit 10;

EOF
```

> Output

```
root@docpg-cls1-pg4:/# psql -h localhost -U postgres -d dba << 'EOF'
INSERT INTO public.multi_dc_failover_test (action)
VALUES ('During DR situation: pg4 is primary'),
      ('During DR situation: This is written from DR site');

SELECT * FROM public.multi_dc_failover_test ORDER BY create_datetime DESC limit 10;

EOF

INSERT 0 2
        create_datetime        |                      action                       
-------------------------------+---------------------------------------------------
 2026-06-10 05:49:01.959929+00 | During DR situation: pg4 is primary
 2026-06-10 05:49:01.959929+00 | During DR situation: This is written from DR site
 2026-06-10 05:38:03.774701+00 | Initial state: pg1 is primary
(3 rows)
```


### Step 9 — Bring Old Primary Cluster Back Up

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

# Check old primary cluster health
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml list
```

> Output -
```
|------------$ docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml list
+ Cluster: docpg-cls1 (7650002457948901374) --+---------+----+-----------+------------------+
| Member         | Host        | Role         | State   | TL | Lag in MB | Tags             |
+----------------+-------------+--------------+---------+----+-----------+------------------+
| docpg-cls1-pg1 | 172.18.0.11 | Sync Standby | stopped |    |   unknown |                  |
+----------------+-------------+--------------+---------+----+-----------+------------------+
| docpg-cls1-pg2 | 172.18.0.12 | Replica      | stopped |    |   unknown |                  |
+----------------+-------------+--------------+---------+----+-----------+------------------+
| docpg-cls1-pg3 | 172.18.0.13 | Replica      | stopped |    |   unknown | nofailover: true |
|                |             |              |         |    |           | nosync: true     |
+----------------+-------------+--------------+---------+----+-----------+------------------+
 Maintenance mode: on
```

Wait for patroni service to start, and patronictl command to return member list

> In DR Drill, the old primary members would NOT come online. Would be in `STOPPED` state due to `maintenance` mode config before DR promotion.

> **⚠️ Do not allow application traffic to this cluster.**
> It holds a stale copy of data and will be demoted to standby in the next steps.

---

### Step 10 — Add `standby_cluster` Config to Old Primary Cluster

Write the `standby_cluster` block into the old cluster's DCS, pointing it at pg4. 
Patroni propagates this to all members automatically.

The old primary cluster will connect to the new primary (pg4) and stream using the **`standby_cluster_slot`** (which we permanently provisioned in pg4's DCS back in Step 6).

> [! CRITICAL] If old primary cluster is NOT in `maintenance` mode, then put it in `maintenance` mode before adding `standby_cluster` config.

```bash
patronictl -c /etc/patroni/patroni.yml pause --wait docpg-cls1

patronictl -c /etc/patroni/patroni.yml list
```

> Output -
```
root@docpg-cls1-pg4:/# patronictl -c /etc/patroni/patroni.yml pause --wait docpg-cls1

'pause' request sent, waiting until it is recognized by all nodes
Success: cluster management is paused

root@docpg-cls1-pg4:/# patronictl -c /etc/patroni/patroni.yml list

+ Cluster: docpg-cls1 (7650002457948901374) --------+----+-----------+
| Member         | Host        | Role    | State    | TL | Lag in MB |
+----------------+-------------+---------+----------+----+-----------+
| docpg-cls1-pg4 | 172.18.0.14 | Leader  | running  | 7   |   unknown |
+----------------+-------------+---------+----------+----+-----------+
 Maintenance mode: on
```

Now, put it in `standby_cluster` config state.

```bash
# Run from any member of the old primary cluster.
# The change is stored in etcd and applies cluster-wide.
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "standby_cluster.host=docpg-cls1-pg4" \
  --set "standby_cluster.port=5432" \
  --set "standby_cluster.primary_slot_name=standby_cluster_slot" \
  --set "slots.standby_cluster_slot.type=null"

# Check old primary cluster health
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml list
```



> Output -
```
|------------$ docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
+ Cluster: docpg-cls1 (7649631878658509655) --+---------+----+-----------+------------------+
| Member         | Host        | Role         | State   | TL | Lag in MB | Tags             |
+----------------+-------------+--------------+---------+----+-----------+------------------+
| docpg-cls1-pg1 | 172.18.0.11 | Replica      | stopped |    |   unknown |                  |
+----------------+-------------+--------------+---------+----+-----------+------------------+
| docpg-cls1-pg2 | 172.18.0.12 | Sync Standby | stopped |    |   unknown |                  |
+----------------+-------------+--------------+---------+----+-----------+------------------+
| docpg-cls1-pg3 | 172.18.0.13 | Replica      | stopped |    |   unknown | nofailover: true |
|                |             |              |         |    |           | nosync: true     |
+----------------+-------------+--------------+---------+----+-----------+------------------+
 Maintenance mode: on


|------------$ docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "standby_cluster.host=docpg-cls1-pg4" \
  --set "standby_cluster.port=5432" \
  --set "standby_cluster.primary_slot_name=standby_cluster_slot" \
  --set "slots.standby_cluster_slot.type=null"
--- 
+++ 
@@ -76,9 +76,10 @@
   use_pg_rewind: true
   use_slots: true
 retry_timeout: 10
-slots:
-  standby_cluster_slot:
-    type: physical
+standby_cluster:
+  host: docpg-cls1-pg4
+  port: 5432
+  primary_slot_name: standby_cluster_slot
 synchronous_mode: true
 synchronous_mode_strict: false
 synchronous_node_count: 1
Configuration changed
```

Verify the config was written to DCS:

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml show-config docpg-cls1 | grep -A5 standby_cluster
# ✅ host: 172.18.0.14, port: 5432, primary_slot_name: standby_cluster_slot
```

> Output -

```
|------------$ docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml show-config docpg-cls1 | grep -A5 standby_cluster
standby_cluster:
  host: docpg-cls1-pg4
  port: 5432
  primary_slot_name: standby_cluster_slot
synchronous_mode: true
synchronous_mode_strict: false
synchronous_node_count: 1
ttl: 30
```

---

### Step 11 - Observe the Cluster State & Timeline

> Timeline situation on new primary cluster (pg4) - Timeline 3

```bash
|------------$ docker exec docpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list

+ Cluster: docpg-cls1 (7649631878658509655) ------+----+-----------+
| Member         | Host        | Role   | State   | TL | Lag in MB |
+----------------+-------------+--------+---------+----+-----------+
| docpg-cls1-pg4 | 172.18.0.14 | Leader | running |  3 |           |
+----------------+-------------+--------+---------+----+-----------+
```

> Timeline situation on old primary cluster (pg1/pg2/pg3)

```bash
|------------$ docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list

+ Cluster: docpg-cls1 (7649631878658509655) -------+----+-----------+------------------+
| Member         | Host        | Role    | State   | TL | Lag in MB | Tags             |
+----------------+-------------+---------+---------+----+-----------+------------------+
| docpg-cls1-pg1 | 172.18.0.11 | Replica | stopped |    |   unknown |                  |
+----------------+-------------+---------+---------+----+-----------+------------------+
| docpg-cls1-pg2 | 172.18.0.12 | Replica | stopped |    |   unknown |                  |
+----------------+-------------+---------+---------+----+-----------+------------------+
| docpg-cls1-pg3 | 172.18.0.13 | Replica | stopped |    |   unknown | nofailover: true |
|                |             |         |         |    |           | nosync: true     |
+----------------+-------------+---------+---------+----+-----------+------------------+
 Maintenance mode: on
```

---

> [! CAUTION]
> Since old primary was put in maintenance mode before the DR promotion, both new standby cluster (pg1/pg2/pg3) and new primary cluster (pg4) are at same timeline (TL3).
> Since both clusters are on same timeline, there is no need to increase the timeline on new primary cluster by doing switchover/failover.

> [! IMPORTANT]
> If new primary cluster has more than 1 member, the switchover/failover will help in increasing Timeline. This would make multiple DC setup more robust.

```bash
# Failover to next node to increase timeline. Repeat this 2 times (TL new = TL old + 4)
patronictl -c /etc/patroni/patroni.yml switchover docpg-cls1 --force
patronictl -c /etc/patroni/patroni.yml failover docpg-cls1 --candidate docpg-cls1-pg1 --force
```

---

### Step 12 - Remove old primary cluster, ie, new standby cluster (pg1/pg2/pg3) from maintenance mode

```bash
echo "=== Resume old primary cluster (pg1/pg2/pg3) ==="
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml resume --wait docpg-cls1

# Check the cluster(s) state
echo "=== Check new primary cluster (pg4) ==="
docker exec docpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
echo "=== Check new standby cluster (pg1/pg2/pg3) ==="
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

> Output -

```
|------------$ echo "=== Check new primary cluster (pg4) ==="
docker exec docpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
echo "=== Check new standby cluster (pg1/pg2/pg3) ==="
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list

=== Check new primary cluster (pg4) ===
+ Cluster: docpg-cls1 (7649631878658509655) ------+----+-----------+
| Member         | Host        | Role   | State   | TL | Lag in MB |
+----------------+-------------+--------+---------+----+-----------+
| docpg-cls1-pg4 | 172.18.0.14 | Leader | running |  3 |           |
+----------------+-------------+--------+---------+----+-----------+

=== Check new standby cluster (pg1/pg2/pg3) ===
+ Cluster: docpg-cls1 (7650002457948901374) -------------------+----+-----------+------------------+
| Member         | Host        | Role    | State               | TL | Lag in MB | Tags             |
+----------------+-------------+---------+---------------------+----+-----------+------------------+
| docpg-cls1-pg1 | 172.18.0.11 | Replica | in archive recovery |  2 |         0 |                  |
+----------------+-------------+---------+---------------------+----+-----------+------------------+
| docpg-cls1-pg2 | 172.18.0.12 | Replica | streaming           |  3 |         0 |                  |
+----------------+-------------+---------+---------------------+----+-----------+------------------+
| docpg-cls1-pg3 | 172.18.0.13 | Replica | in archive recovery |  3 |         0 | nofailover: true |
|                |             |         |                     |    |           | nosync: true     |
+----------------+-------------+---------+---------------------+----+-----------+------------------+
```

---

### Step 13 - Make data entries on new primary cluster after old primary cluster has joined as new standby cluster
```bash
psql -h localhost -U postgres -d dba << 'EOF'
INSERT INTO public.multi_dc_failover_test (action)
VALUES ('During DR situation: pg1 cluster has joined as new standby cluster');

SELECT * FROM public.multi_dc_failover_test ORDER BY create_datetime DESC limit 10;

EOF
```

> Output

```
root@docpg-cls1-pg4:/# psql -h localhost -U postgres -d dba << 'EOF'
INSERT INTO public.multi_dc_failover_test (action)
VALUES ('During DR situation: pg1 cluster has joined as new standby cluster');

SELECT * FROM public.multi_dc_failover_test ORDER BY create_datetime DESC limit 10;

EOF

INSERT 0 1
        create_datetime        |                               action                               
-------------------------------+--------------------------------------------------------------------
 2026-06-10 06:25:19.277654+00 | During DR situation: pg1 cluster has joined as new standby cluster
 2026-06-10 05:49:01.959929+00 | During DR situation: pg4 is primary
 2026-06-10 05:49:01.959929+00 | During DR situation: This is written from DR site
 2026-06-10 05:38:03.774701+00 | Initial state: pg1 is primary
(4 rows)
```

---

### Failback to old primary cluster

```bash
psql -h localhost -U postgres -d dba << 'EOF'
INSERT INTO public.multi_dc_failover_test (action)
VALUES ('During DR situation: Failback. pg1 is promoted to primary');

INSERT INTO public.multi_dc_failover_test (action)
VALUES ('During DR situation: Failback. This is written from primary site');

INSERT INTO public.multi_dc_failover_test (action)
VALUES ('During DR situation: Failback. pg4 site is down.');

SELECT * FROM public.multi_dc_failover_test ORDER BY create_datetime DESC limit 10;

EOF
```

