# DR Split Brain Resolution Guide

## When Does Split Brain Occur?

Split brain arises when the **old primary cluster (pg1/pg2/pg3) comes back online after an
unplanned outage** while the **standby cluster (pg4) has already been promoted** to a new primary.
Both sides now believe they own the dataset and Patroni on pg1/pg2/pg3 may elect a Leader.

```
OLD PRIMARY  →  went down unplanned
                ↓
STANDBY (pg4)  →  promoted (timeline advances, e.g. TL3 → TL4)
                ↓
OLD PRIMARY  →  comes back online, elects a leader on its OWN timeline (TL3+)
                ↓
SPLIT BRAIN: two writable primaries, diverged WAL histories
```

## Topology Reference

| Cluster | Members | Role (post-split-brain) | Container IP |
|---------|---------|------------------------|-------------|
| **New Primary** | docpg-cls1-pg4 | Leader (pg4 was promoted) | 172.18.0.14 |
| **Old Primary** (stale) | docpg-cls1-pg1 | Stale Leader — must be demoted | 172.18.0.11 |
| | docpg-cls1-pg2 | Replica (stale) | 172.18.0.12 |
| | docpg-cls1-pg3 | Replica (stale) | 172.18.0.13 |

---

## Resolution Runbook

> **⚠ Work fast.** Every write accepted by the old primary widens the divergence.
> Run Steps 1 and 2 first — in parallel if possible.

---

### Step 1 — Fence the Old Primary: Block All Application Writes Immediately

The moment you detect split brain, cut off application traffic to the old primary.

```bash
# Kill all non-superuser connections on old primary leader
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres -c "
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE usename NOT IN ('postgres', 'replicator')
  AND pid <> pg_backend_pid();"

# Set connection limit to 0 on all application databases
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres -c "
  ALTER DATABASE dba CONNECTION LIMIT 0;"
```

Then immediately put the old primary cluster into Patroni **maintenance mode** to prevent automatic
leader elections from restarting:

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml pause --wait docpg-cls1
```

---

### Step 2 — Identify the Authoritative Primary and Assess Divergence

Check the timeline and latest LSN on **both** sides to understand how far apart they are.

```bash
# --- New primary (pg4) ---
docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres -c \
  "SELECT pg_is_in_recovery(), timeline_id, redo_lsn FROM pg_control_checkpoint();"

docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres -c \
  "SELECT pg_current_wal_lsn();"

# --- Old primary leader (pg1) ---
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres -c \
  "SELECT pg_is_in_recovery(), timeline_id, redo_lsn FROM pg_control_checkpoint();"

docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres -c \
  "SELECT pg_current_wal_lsn();"
```

**Interpret the output:**

| Scenario | Meaning | Fix |
|---|---|---|
| pg4 timeline > pg1 timeline | pg4 promoted cleanly after pg1 went down; pg1 has no divergent writes | `pg_rewind` (fast path) |
| pg1 timeline = pg4 timeline | Both advanced independently → true split brain with possible data divergence | `pg_rewind` or `reinit` |
| pg1 timeline > pg4 timeline | pg1 accepted writes after pg4 promoted → data may be lost on demotion | `reinit` (safest) |

---

### Step 3 — Stop Patroni on Old Primary Cluster Members

Stop replicas first, then the stale leader, to prevent any further writes or elections.

```bash
docker exec docpg-cls1-pg3 systemctl stop patroni
docker exec docpg-cls1-pg2 systemctl stop patroni
docker exec docpg-cls1-pg1 systemctl stop patroni
```

Verify all stopped:

```bash
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n patroni: "
  docker exec $n systemctl is-active patroni 2>&1
done
# ✅ Expected: inactive (or failed) for all three
```

---

### Step 4 — Rewind or Reinitialise the Old Primary Cluster Members

Choose the correct method based on Step 2's assessment.

#### Option A — `pg_rewind` (preferred when timelines diverged cleanly)

`pg_rewind` rewinds pg1's data directory to the point where it diverged from pg4's timeline,
then lets Patroni re-apply WAL from the archive. This is non-destructive: only divergent WAL
blocks are overwritten.

```bash
# Run pg_rewind on each old primary member against the new primary (pg4)
for node in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== Rewinding $node ==="
  docker exec $node bash -c "
    /usr/lib/postgresql/18/bin/pg_rewind \
      --target-pgdata=/var/lib/postgresql/18/main \
      --source-server='host=172.18.0.14 port=5432 user=postgres dbname=postgres' \
      --progress \
      --no-ensure-shutdown
  "
done
```

After `pg_rewind` completes on each node, verify:

```bash
docker exec docpg-cls1-pg1 bash -c \
  "/usr/lib/postgresql/18/bin/pg_controldata /var/lib/postgresql/18/main \
   | grep -E 'Timeline|checkpoint'"
# ✅ TimeLineID should now match pg4's timeline
```

#### Option B — `patronictl reinit` (use when pg_rewind fails or data is unrecoverable)

This wipes the data directory and clones from the new primary. **All local data divergence is
discarded.** Suitable when the timeline mismatch is too wide for pg_rewind.

```bash
# Start Patroni first (it is needed to issue reinit), but keep pause mode on
docker exec docpg-cls1-pg1 systemctl start patroni
docker exec docpg-cls1-pg2 systemctl start patroni
docker exec docpg-cls1-pg3 systemctl start patroni

# Reinit replicas first, then the stale leader
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml reinit docpg-cls1 docpg-cls1-pg3 --force
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml reinit docpg-cls1 docpg-cls1-pg2 --force
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml reinit docpg-cls1 docpg-cls1-pg1 --force
```

> **Note:** `reinit` streams a fresh base backup from the new standby leader (pg4 → pg1 via the
> `standby_cluster_slot`). Make sure Step 5 is done **before** resuming so Patroni knows where to
> stream from.

---

### Step 5 — Write `standby_cluster` Config to Old Primary Cluster DCS

Point the old cluster at pg4 as its upstream. This tells Patroni to manage pg1/pg2/pg3
as a streaming standby cluster rather than an independent primary.

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "standby_cluster.host=docpg-cls1-pg4" \
  --set "standby_cluster.port=5432" \
  --set "standby_cluster.primary_slot_name=standby_cluster_slot" \
  --set "slots.standby_cluster_slot.type=null"
```

Verify the config was applied:

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml show-config docpg-cls1 | grep -A5 standby_cluster
# ✅ Expected: host: docpg-cls1-pg4, port: 5432, primary_slot_name: standby_cluster_slot
```

Also verify `standby_cluster_slot` is active on pg4 (should have been provisioned during
pg4's promotion per the DR_FAILOVER_GUIDE Step 6):

```bash
docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres -c "
SELECT slot_name, slot_type, active, restart_lsn
FROM pg_replication_slots
WHERE slot_name = 'standby_cluster_slot';"
# ✅ active = t  (becomes true once pg1 connects)
```

If the slot does **NOT** exist on pg4, create it now before resuming:

```bash
docker exec docpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config docpg-cls1 --force \
  --set "slots.standby_cluster_slot.type=physical"
```

---

### Step 6 — Remove Old Primary Cluster from Maintenance Mode

```bash
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml resume --wait docpg-cls1
```

Start Patroni on any nodes that were fully stopped (not just paused):

```bash
docker exec docpg-cls1-pg1 systemctl start patroni
docker exec docpg-cls1-pg2 systemctl start patroni
docker exec docpg-cls1-pg3 systemctl start patroni
```

---

### Step 7 — Verify Old Primary is Now a Healthy Standby

```bash
# On the old primary cluster members — expect Standby Leader + Replicas streaming
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml list docpg-cls1
# ✅ Expected:
# | docpg-cls1-pg1 | ... | Standby Leader | streaming | <TL matching pg4> | 0 |
# | docpg-cls1-pg2 | ... | Replica        | streaming | <TL matching pg4> | 0 |
# | docpg-cls1-pg3 | ... | Replica        | streaming | <TL matching pg4> | 0 |

# Confirm pg1 is in standby/recovery mode
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres -c \
  "SELECT pg_is_in_recovery(), timeline_id FROM pg_control_checkpoint();"
# ✅ pg_is_in_recovery = t

# Check replication lag from pg4 to pg1
docker exec docpg-cls1-pg4 psql -h 172.18.0.14 -U postgres -c "
SELECT application_name, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) AS flush_lag_bytes,
       replay_lag
FROM pg_stat_replication
WHERE application_name = 'docpg-cls1-pg1';"
# ✅ state = streaming, flush_lag_bytes approaching 0
```

---

### Step 8 — Restore Application Connection Limits

Once the old cluster is confirmed to be a healthy standby (not a primary), restore connection
limits so that if it ever needs to serve read traffic in the future, it can.

```bash
docker exec docpg-cls1-pg1 psql -h 172.18.0.11 -U postgres -c "
  ALTER DATABASE dba CONNECTION LIMIT -1;"
```

---

## Timeline Mismatch After Old Primary Returns (Nodes in `start failed` state)

If pg1/pg2/pg3 members enter `start failed` state with:
```
FATAL: requested timeline N is not a child of this server's history
```

This means their local `pg_control` diverges from the pgbackrest archive. Use `reinit` to
wipe and reclone each affected member from the current standby leader (pg1) once it is healthy:

```bash
# First bring pg1 back as standby leader (via Steps 4B and 5-6 above)
# Then reinit the failed members
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml reinit docpg-cls1 docpg-cls1-pg2 --force
docker exec docpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml reinit docpg-cls1 docpg-cls1-pg3 --force
```

---

## Quick Reference Decision Tree

```
Old primary comes back online after pg4 was promoted
       |
       ├── Is pg1 cluster still in maintenance mode? ──yes──> Skip Step 1 (already fenced)
       |         no
       |          ↓
       |    FENCE IMMEDIATELY (Step 1)
       |
       ├── pg4 TL > pg1 TL? ──yes──> pg_rewind (Step 4A) → configure standby_cluster (Step 5)
       |
       ├── pg4 TL = pg1 TL? ──yes──> pg_rewind first; if fails → reinit (Step 4B)
       |
       └── pg1 TL > pg4 TL? ──yes──> reinit (Step 4B) → configure standby_cluster (Step 5)
                                      ⚠ Data written to old primary after pg4 promoted is LOST
```