# DR Switchover Guide - Real Disaster Switchover

In graceful switchover, DBA coordinates with application teams to perform a graceful switchover.
DBA controls the unavailability of primary cluster nodes, and application teams perform a graceful
shutdown of their respective applications.

In real disaster switchover, DBA coordinates with application teams to perform a real disaster switchover.
DBA has to promote standby cluster to primary without any coordination with application teams.

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

## Real DR Switchover — Step-by-Step Runbook

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
+ Cluster: docpg-cls1 (7649716325149331488) --+-----------+----+-----------+------------------+
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
+ Cluster: docpg-cls1 (7649716325149331488) ----+-----------+----+-----------+------------------+
| Member         | Host        | Role           | State     | TL | Lag in MB | Tags             |
+----------------+-------------+----------------+-----------+----+-----------+------------------+
| docpg-cls1-pg4 | 172.18.0.14 | Standby Leader | streaming |  2 |           |                  |
+----------------+-------------+----------------+-----------+----+-----------+------------------+
| docpg-cls1-pg5 | 172.18.0.15 | Replica        | streaming |  2 |         0 |                  |
+----------------+-------------+----------------+-----------+----+-----------+------------------+
| docpg-cls1-pg6 | 172.18.0.16 | Replica        | streaming |  2 |         0 | nofailover: true |
|                |             |                |           |    |           | nosync: true     |
+----------------+-------------+----------------+-----------+----+-----------+------------------+
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

---

### Step 2 — Stop Primary Cluster

```bash
docker stop docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3
```

Verify all three are down:

```bash
docker ps --filter name=docpg-cls1-pg --format "table {{.Names}}\t{{.Status}}"
# ✅ pg1, pg2, pg3 should be absent or show Exited
```

---

### Step 3 — Promote Standby Cluster to Primary

Remove the `standby_cluster` block from the DCS configuration. 
Patroni on `docpg-cls1-pg4` detects this change and promotes PostgreSQL from a streaming standby to a normal read-write primary.
At the same time, provision a permanent physical slot (`standby_cluster_slot`) so that the old primary cluster can securely stream from pg4 when it returns as the new standby.

```bash
# Remove the `standby_cluster` block from the DCS configuration.
  # In real disaster, we don't want wal logs to fill the disk. So NOT creating a physical slot at same time
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "standby_cluster=null"

# Create a permanent physical slot for the old primary cluster when old primary comes online
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "slots.standby_cluster_slot.type=physical"

# Check cluster state again
docker exec docpg-cls1-pg4 \
    patronictl -c /etc/patroni/patroni.yml list
```

> Output -
```
|------------$ docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "standby_cluster=null"

--- 
+++ 
@@ -75,10 +75,6 @@
   use_pg_rewind: true
   use_slots: true
 retry_timeout: 10
-standby_cluster:
-  host: 172.18.0.10
-  port: 5432
-  primary_slot_name: standby_cluster_slot
 synchronous_mode: true
 synchronous_mode_strict: false
 synchronous_node_count: 1
Configuration changed


|------------$ docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "slots.standby_cluster_slot.type=physical"

--- 
+++ 
@@ -75,6 +75,9 @@
   use_pg_rewind: true
   use_slots: true
 retry_timeout: 10
+slots:
+  standby_cluster_slot:
+    type: physical
 synchronous_mode: true
 synchronous_mode_strict: false
 synchronous_node_count: 1
Configuration changed


|------------$ docker exec docpg-cls1-pg4 \
    patronictl -c /etc/patroni/patroni.yml list
+ Cluster: docpg-cls1 (7649716325149331488) --+-----------+----+-----------+------------------+
| Member         | Host        | Role         | State     | TL | Lag in MB | Tags             |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg4 | 172.18.0.14 | Leader       | running   |  3 |           |                  |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg5 | 172.18.0.15 | Sync Standby | streaming |  3 |         0 |                  |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg6 | 172.18.0.16 | Replica      | streaming |  3 |         0 | nofailover: true |
|                |             |              |           |    |           | nosync: true     |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
```

---

### Step 4 - Make data entries on new primary cluster during DR situation
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

---

### Step 5 - For single member primary cluster, `Add new replicas` in cluster as we don't know how long the Disaster will last

```
# Build new containers for new replicas
ansible-playbook -i hosts.yml playbook-setup-standby-cluster-containers.yml 2>&1 | tee logs/playbook-setup-standby-cluster-containers.yml.log

# Check containers that are online
docker ps --filter name=docpg-cls1-pg --format "table {{.Names}}\t{{.Status}}"

# Add standby cluster replicas (default):
ansible-playbook -i hosts.yml playbook-add-replicas.yml --vault-password-file=vault-pass 2>&1 \
    | tee logs/playbook-add-replicas.log

# DO NOT RUN THIS: Add primary cluster replicas:
ansible-playbook -i hosts.yml playbook-add-replicas.yml --vault-password-file=vault-pass \
  -e host_group_for_new_replica=primary_cluster 2>&1 | tee logs/playbook-add-replicas.log
```

---

### Step 6 — Bring Old Primary Cluster Back Up

Start the old primary cluster containers and Patroni. Because the old cluster's etcd DCS still
holds the previous leader state and has **no `standby_cluster` config yet**, Patroni will elect
a leader among pg1/pg2/pg3. This is expected — the cluster comes up momentarily as a standalone
(non-standby) primary. **Do not allow application writes to it.** The standby config is applied
in Next Step.

```bash
# Start containers if they were stopped in Step 5
docker start docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3

```

> **⚠️ Do not allow application traffic to this cluster.**
> It holds a stale copy of data and will be demoted to standby in the next steps.

---

### Step 7 — Set old primary cluster into maintenance mode

```bash
# Set to maintenance mode
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml pause --wait docpg-cls1

# Verify maintenance mode
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

> Output -

```
root@docpg-cls1-pg1:/# 
root@docpg-cls1-pg1:/# patronictl list

+ Cluster: docpg-cls1 (7649716325149331488) --+-----------+----+-----------+------------------+
| Member         | Host        | Role         | State     | TL | Lag in MB | Tags             |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg1 | 172.18.0.11 | Leader       | running   |  3 |           |                  |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg2 | 172.18.0.12 | Sync Standby | streaming |  3 |         0 |                  |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg3 | 172.18.0.13 | Replica      | streaming |  3 |         0 | nofailover: true |
|                |             |              |           |    |           | nosync: true     |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
 Maintenance mode: on
```

> [!NOTE] We can notice that old primary cluster is in `maintenance mode`. Has a `Leader` and one Timeline higher than new primary cluster.

---

### Step 8 — Add `standby_cluster` Config to Old Primary Cluster

Write the `standby_cluster` block into the old cluster's DCS, pointing it at pg4. 
Patroni propagates this to all members automatically.

The old primary cluster will connect to the new primary (pg4) and stream using the **`standby_cluster_slot`** (which we permanently provisioned in pg4's DCS back in Step 6).

```bash
# Update cluster 
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "standby_cluster.host=docpg-cls1-pg4" \
  --set "standby_cluster.port=5432" \
  --set "standby_cluster.primary_slot_name=standby_cluster_slot" \
  --set "slots.standby_cluster_slot.type=null"

# Verify maintenance mode
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

> Output -
```
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


root@docpg-cls1-pg1:/# patronictl -c /etc/patroni/patroni.yml list
+ Cluster: docpg-cls1 (7650002457948901374) ----+-----------+----+-----------+------------------+
| Member         | Host        | Role           | State     | TL | Lag in MB | Tags             |
+----------------+-------------+----------------+-----------+----+-----------+------------------+
| docpg-cls1-pg1 | 172.18.0.11 | Standby Leader | running   | 11 |           |                  |
+----------------+-------------+----------------+-----------+----+-----------+------------------+
| docpg-cls1-pg2 | 172.18.0.12 | Replica        | streaming | 11 |         0 |                  |
+----------------+-------------+----------------+-----------+----+-----------+------------------+
| docpg-cls1-pg3 | 172.18.0.13 | Replica        | streaming | 11 |         0 | nofailover: true |
|                |             |                |           |    |           | nosync: true     |
+----------------+-------------+----------------+-----------+----+-----------+------------------+

root@docpg-cls1-pg4:/# patronictl -c /etc/patroni/patroni.yml list
+ Cluster: docpg-cls1 (7650002457948901374) ------+----+-----------+
| Member         | Host        | Role   | State   | TL | Lag in MB |
+----------------+-------------+--------+---------+----+-----------+
| docpg-cls1-pg4 | 172.18.0.14 | Leader | running | 10 |           |
+----------------+-------------+--------+---------+----+-----------+
```

> [!CRITICAL] We can see from above output that old primary cluster timeline is greater than new primary cluster timeline.

---

### Step 9 - If `Timeline` issue is present (old primary TL > new primary TL), then Increment new primary cluster timeline

```
# **** Run 01
patronictl -c /etc/patroni/patroni.yml failover docpg-cls1 --candidate docpg-cls1-pg5 --force
sleep 15
patronictl -c /etc/patroni/patroni.yml failover docpg-cls1 --candidate docpg-cls1-pg4 --force

# **** Run 02
patronictl -c /etc/patroni/patroni.yml failover docpg-cls1 --candidate docpg-cls1-pg5 --force
sleep 15
patronictl -c /etc/patroni/patroni.yml failover docpg-cls1 --candidate docpg-cls1-pg4 --force

```

---

### Step 10 - If old primary (pg1/pg2/pg3) got demoted to standby, and new primary got higher timeline, then take it out of `maintenance` mode

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
root@docpg-cls1-pg1:/# patronictl -c /etc/patroni/patroni.yml resume --wait docpg-cls1

'resume' request sent, waiting until it is recognized by all nodes
Success: cluster management is resumed
root@docpg-cls1-pg1:/# 


|------------$ echo "=== Check new primary cluster (pg4) ==="
docker exec docpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
echo "=== Check new standby cluster (pg1/pg2/pg3) ==="
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list

=== Check new primary cluster (pg4) ===
+ Cluster: docpg-cls1 (7649716325149331488) --+-----------+----+-----------+------------------+
| Member         | Host        | Role         | State     | TL | Lag in MB | Tags             |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg4 | 172.18.0.14 | Leader       | running   |  7 |           |                  |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg5 | 172.18.0.15 | Sync Standby | streaming |  7 |         0 |                  |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| docpg-cls1-pg6 | 172.18.0.16 | Replica      | streaming |  7 |         0 | nofailover: true |
|                |             |              |           |    |           | nosync: true     |
+----------------+-------------+--------------+-----------+----+-----------+------------------+

=== Check new standby cluster (pg1/pg2/pg3) ===
+ Cluster: docpg-cls1 (7649716325149331488) ---------+----+-----------+------------------+
| Member         | Host        | Role    | State     | TL | Lag in MB | Tags             |
+----------------+-------------+---------+-----------+----+-----------+------------------+
| docpg-cls1-pg1 | 172.18.0.11 | Replica | stopped   |    |   unknown |                  |
+----------------+-------------+---------+-----------+----+-----------+------------------+
| docpg-cls1-pg2 | 172.18.0.12 | Replica | stopped   |    |   unknown |                  |
+----------------+-------------+---------+-----------+----+-----------+------------------+
| docpg-cls1-pg3 | 172.18.0.13 | Replica | streaming |  7 |         0 | nofailover: true |
|                |             |         |           |    |           | nosync: true     |
+----------------+-------------+---------+-----------+----+-----------+------------------+
```

---

### Step 12 - Make data entries on new primary cluster after old primary cluster has joined as new standby cluster
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

