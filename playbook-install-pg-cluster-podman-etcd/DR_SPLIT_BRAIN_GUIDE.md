# DR Split Brain Resolution Guide

## What Is Split Brain?

Split brain is a condition where **two independent PostgreSQL clusters simultaneously believe they
are the authoritative primary** for the same dataset. Both accept writes, their WAL histories
diverge, and without intervention, data on one side will be permanently lost.

In a Patroni multi-DC setup, this happens specifically when:
1. The primary cluster (`podpg-cls1-pg1/pg2/pg3`) suffers an **unplanned outage**.
2. The standby cluster (`podpg-cls1-pg4`) is **promoted** to a new primary (timeline advances).
3. The old primary cluster **recovers and comes back online** — but with no `standby_cluster` config,
   Patroni elects a leader among pg1/pg2/pg3, creating a second independent primary.

---

## Real-World Example: 2026-06-09 on podpg-cls1

### Initial state (before split brain)

```
podpg-cls1-pg1  Leader        TL2  running   (primary cluster)
podpg-cls1-pg2  Sync Standby  TL2  streaming
podpg-cls1-pg3  Replica       TL2  streaming
podpg-cls1-pg4  Standby Leader TL1 streaming  (DR standby cluster)
```

### How the split brain was created

**Step A** — `podpg-cls1-pg1/pg2/pg3` containers were stopped (`podman stop`), simulating
a datacenter outage. `pg4` entered `in archive recovery` state:

```
podpg-cls1-pg4  Standby Leader  TL1  in archive recovery
```

**Step B** — `podpg-cls1-pg4` was promoted by removing the `standby_cluster` block from
the DCS. Timeline advanced: TL1 → TL2 → TL3.

```
podpg-cls1-pg4  Leader  TL3  running  ← new authoritative primary
```

**Step C** — `podman start podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3`. The containers
came back online with their old etcd DCS state (no `standby_cluster` config). Patroni elected
`podpg-cls1-pg2` as the leader, creating its own timeline promotion: TL3 → TL4.

```
podpg-cls1-pg1  Sync Standby  TL4  streaming  ← stale, diverged
podpg-cls1-pg2  Leader        TL4  running    ← SPLIT BRAIN: second primary
podpg-cls1-pg3  Replica       TL4  streaming  ← stale, diverged
```

### Why it is dangerous

At this point:
- **pg4 (TL3)** is the correct primary. Any application writes here are valid.
- **pg2 (TL4)** is a stale primary. Any writes here are silently diverged from pg4's history and
  will be **permanently lost** when the split brain is resolved.
- The two sides diverged at WAL location `0/7000000` on timeline 3.

### Topology reference (post-split-brain)

| Node | Role | Timeline | IP | Status |
|------|------|----------|----|--------|
| podpg-cls1-pg4 | **Authoritative New Primary** | TL3 | 172.18.0.14 | ✅ Keep |
| podpg-cls1-pg2 | **Stale Leader** (must be demoted) | TL4 | 172.18.0.12 | ⚠ Fence |
| podpg-cls1-pg1 | Stale Replica | TL4 | 172.18.0.11 | ⚠ Rewind |
| podpg-cls1-pg3 | Stale Replica | TL4 | 172.18.0.13 | ⚠ Rewind |

---

## How to Detect Split Brain

```bash
# Check both clusters simultaneously
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

**Split brain is confirmed when BOTH outputs show a `Leader` in `running` state:**

```
# pg4 side
+ Cluster: podpg-cls1 (7649421311168285384) ------+----+-----------+
| Member         | Host        | Role   | State   | TL | Lag in MB |
+----------------+-------------+--------+---------+----+-----------+
| podpg-cls1-pg4 | 172.18.0.14 | Leader | running |  3 |           |
+----------------+-------------+--------+---------+----+-----------+

# pg1/pg2/pg3 side — SECOND LEADER = SPLIT BRAIN
+ Cluster: podpg-cls1 (7649421311168285384) --+-----------+----+-----------+
| Member         | Host        | Role         | State     | TL | Lag in MB |
+----------------+-------------+--------------+-----------+----+-----------+
| podpg-cls1-pg1 | 172.18.0.11 | Sync Standby | streaming |  4 |         0 |
| podpg-cls1-pg2 | 172.18.0.12 | Leader       | running   |  4 |           |
| podpg-cls1-pg3 | 172.18.0.13 | Replica      | streaming |  4 |         0 |
+----------------+-------------+--------------+-----------+----+-----------+
```

---

## Resolution Runbook

> **⚠ Work fast.** Every write accepted by the old primary widens the divergence.
> Run Steps 1 and 2 simultaneously if possible.

---

### Step 1 — Fence the Old Primary: Block All Application Writes Immediately

The moment you detect split brain, cut off application traffic to the stale leader.
Use the **local Unix socket** (`-U postgres` without `-h`) — the stale primary rejects
remote connections if `pg_hba.conf` requires a password that isn't in `.pgpass`.

```bash
# Identify which node became the stale leader
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
# In the 2026-06-09 incident: podpg-cls1-pg2 was the stale leader

# Kill all non-superuser connections via local socket on the stale leader
podman exec podpg-cls1-pg2 psql -U postgres -c "
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE usename NOT IN ('postgres', 'replicator')
  AND pid <> pg_backend_pid();"
```

> Output:
```
 count
-------
     0
(1 row)
```

Immediately put the old cluster into Patroni **maintenance mode** to prevent automatic
leader elections while you work:

```bash
podman exec podpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml pause --wait podpg-cls1
```

> Output (if not already paused):
```
Success: cluster management is paused
```

> Output (if already paused from a previous DR drill):
```
Error: Cluster is already paused
```

Confirm maintenance mode is active:

```bash
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

> Output:
```
+ Cluster: podpg-cls1 (7649421311168285384) --+-----------+----+-----------+------------------+
| Member         | Host        | Role         | State     | TL | Lag in MB | Tags             |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
| podpg-cls1-pg1 | 172.18.0.11 | Sync Standby | streaming |  4 |         0 |                  |
| podpg-cls1-pg2 | 172.18.0.12 | Leader       | running   |  4 |           |                  |
| podpg-cls1-pg3 | 172.18.0.13 | Replica      | streaming |  4 |         0 | nofailover: true |
+----------------+-------------+--------------+-----------+----+-----------+------------------+
 Maintenance mode: on
```

---

### Step 2 — Assess Timeline Divergence

Check timeline and current LSN on both the new primary (pg4) and the stale leader (pg2).

```bash
# New primary (pg4)
podman exec podpg-cls1-pg4 psql -U postgres -At -c \
  "SELECT 'is_in_recovery='||pg_is_in_recovery()||' tl='||timeline_id||' lsn='||pg_current_wal_lsn()
   FROM pg_control_checkpoint();"

# Stale leader (pg2)
podman exec podpg-cls1-pg2 psql -U postgres -At -c \
  "SELECT 'is_in_recovery='||pg_is_in_recovery()||' tl='||timeline_id||' lsn='||pg_current_wal_lsn()
   FROM pg_control_checkpoint();"
```

> Output from the 2026-06-09 incident:
```
is_in_recovery=false tl=3 lsn=0/70001E0    ← pg4: new primary, TL3

is_in_recovery=false tl=4 lsn=0/7007D60    ← pg2: stale leader, TL4 (HIGHER than pg4!)
```

**Interpretation table:**

| Scenario | What happened | Method |
|---|---|---|
| pg4 TL > stale TL | pg1/pg2/pg3 stayed down while pg4 ran ahead | `pg_rewind` ✅ |
| pg4 TL = stale TL | Both promoted independently | `pg_rewind` ✅, fallback reinit |
| **pg4 TL < stale TL** | **Old primary promoted itself after pg4 — true split brain** | **`pg_rewind` still works** ✅ |

> **Lesson from 2026-06-09:** `pg_rewind` worked correctly even though the stale side (TL4)
> had a *higher* timeline than the new primary (TL3). pg_rewind found the common fork point on
> TL2 and rewound each node cleanly.

---

### Step 3 — Stop Patroni and PostgreSQL on Old Primary Cluster Members

Patroni and PostgreSQL must both be fully stopped before running `pg_rewind`.
Stop replicas first, then the stale leader.

```bash
# Stop Patroni (Patroni will stop PostgreSQL gracefully when it stops)
podman exec podpg-cls1-pg3 systemctl stop patroni
podman exec podpg-cls1-pg1 systemctl stop patroni
podman exec podpg-cls1-pg2 systemctl stop patroni
```

Verify Patroni is stopped, then verify PostgreSQL is also stopped:

```bash
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n patroni: "; podman exec $n systemctl is-active patroni 2>&1
  echo -n "$n postgres: "; podman exec $n bash -c "pgrep -x postgres >/dev/null && echo running || echo stopped"
done
```

> Output after Patroni stop:
```
podpg-cls1-pg1 patroni: inactive
podpg-cls1-pg1 postgres: running      ← PostgreSQL may still be up
podpg-cls1-pg2 patroni: inactive
podpg-cls1-pg2 postgres: running
podpg-cls1-pg3 patroni: inactive
podpg-cls1-pg3 postgres: running
```

If PostgreSQL is still running, stop it cleanly with `pg_ctl`:

```bash
for n in podpg-cls1-pg3 podpg-cls1-pg1 podpg-cls1-pg2; do
  echo "=== Stopping postgres on $n ==="
  podman exec $n su -c \
    "/usr/lib/postgresql/18/bin/pg_ctl stop -D /var/lib/postgresql/18/main -m fast" postgres
done
```

> Output:
```
=== Stopping postgres on podpg-cls1-pg3 ===
waiting for server to shut down.... done
server stopped
=== Stopping postgres on podpg-cls1-pg1 ===
waiting for server to shut down.... done
server stopped
=== Stopping postgres on podpg-cls1-pg2 ===
waiting for server to shut down.... done
server stopped
```

Confirm all PostgreSQL processes are gone:

```bash
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n postgres: "
  podman exec $n bash -c "pgrep -x postgres >/dev/null && echo running || echo stopped"
done
```

> Output:
```
podpg-cls1-pg1 postgres: stopped
podpg-cls1-pg2 postgres: stopped
podpg-cls1-pg3 postgres: stopped
```

---

### Step 4 — Run `pg_rewind` on Each Old Primary Member

`pg_rewind` syncs the stale data directory to match the new primary (pg4).
It finds the last common WAL fork point and copies only the changed data blocks.
The process is non-destructive — no data from pg4 is deleted.

Must be run as the **`postgres` OS user** using `su -c`:

```bash
for node in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo ""; echo "=== pg_rewind on $node (source = pg4) ==="
  podman exec $node su -c "
    /usr/lib/postgresql/18/bin/pg_rewind \
      --target-pgdata=/var/lib/postgresql/18/main \
      --source-server='host=172.18.0.14 port=5432 user=postgres dbname=postgres' \
      --progress \
      --no-ensure-shutdown
  " postgres
  echo "exit: $?"
done
```

> Output from the 2026-06-09 incident (same for all three nodes):
```
=== pg_rewind on podpg-cls1-pg1 (source = pg4) ===
pg_rewind: connected to server
pg_rewind: servers diverged at WAL location 0/7000000 on timeline 3
pg_rewind: rewinding from last common checkpoint at 0/60001C0 on timeline 2
pg_rewind: reading source file list
pg_rewind: reading target file list
pg_rewind: reading WAL in target
pg_rewind: need to copy 84 MB (total source directory size is 110 MB)
    0/86969 kB (0%) copied
86969/86969 kB (100%) copied
pg_rewind: creating backup label and updating control file
pg_rewind: syncing target data directory
pg_rewind: Done!
exit: 0

=== pg_rewind on podpg-cls1-pg2 (source = pg4) ===
... (identical output) ...
pg_rewind: Done!
exit: 0

=== pg_rewind on podpg-cls1-pg3 (source = pg4) ===
... (identical output) ...
pg_rewind: Done!
exit: 0
```

**What pg_rewind did:**
- Found the divergence at `0/7000000` on TL3 — the point where the old primary promoted to TL4
  while pg4 was already on TL3.
- Rewound to the last common checkpoint at `0/60001C0` on TL2.
- Copied 84 MB per node (out of 110 MB total) to make the data directory consistent with pg4.
- Created a `backup_label` file marking the minimum recovery point: `0/7006260` on TL3
  (pg4's last checkpoint at the time of rewind).

---

### Step 5 — Write `standby_cluster` Config to Old Cluster DCS

Start Patroni briefly on one node to issue `patronictl` commands against the old cluster's etcd.
The cluster is still in maintenance mode, so PostgreSQL will not be started yet.

```bash
podman exec podpg-cls1-pg1 systemctl start patroni
sleep 5
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

> Output:
```
+ Cluster: podpg-cls1 (7649421311168285384) --+---------+----+-----------+
| Member         | Host        | Role         | State   | TL | Lag in MB |
+----------------+-------------+--------------+---------+----+-----------+
| podpg-cls1-pg1 | 172.18.0.11 | Sync Standby | stopped |    |   unknown |
+----------------+-------------+--------------+---------+----+-----------+
 Maintenance mode: on
```

Now write the `standby_cluster` config pointing to pg4:

```bash
podman exec podpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config podpg-cls1 --force \
  --set "standby_cluster.host=podpg-cls1-pg4" \
  --set "standby_cluster.port=5432" \
  --set "standby_cluster.primary_slot_name=standby_cluster_slot" \
  --set "slots.standby_cluster_slot.type=null"
```

> Output:
```
---
+++
@@ -88,9 +88,10 @@
   use_pg_rewind: true
   use_slots: true
 retry_timeout: 10
-slots:
-  standby_cluster_slot:
-    type: physical
+standby_cluster:
+  host: podpg-cls1-pg4
+  port: 5432
+  primary_slot_name: standby_cluster_slot
 synchronous_mode: true
 synchronous_mode_strict: false
 synchronous_node_count: 1

Configuration changed
```

Verify `standby_cluster_slot` exists on pg4 (provisioned during pg4's promotion in Step 6 of
DR_FAILOVER_GUIDE). It will show `active=false` until pg1 connects:

```bash
podman exec podpg-cls1-pg4 psql -U postgres -At -c \
  "SELECT slot_name, active FROM pg_replication_slots WHERE slot_name='standby_cluster_slot';"
```

> Output:
```
standby_cluster_slot|f
```

If the slot does **NOT** exist on pg4, create it before proceeding:

```bash
podman exec podpg-cls1-pg4 \
  patronictl -c /etc/patroni/patroni.yml \
  edit-config podpg-cls1 --force \
  --set "slots.standby_cluster_slot.type=physical"
```

---

### Step 6 — Resume Maintenance Mode and Start Patroni on All Nodes

```bash
podman exec podpg-cls1-pg1 \
  patronictl -c /etc/patroni/patroni.yml resume --wait podpg-cls1

podman exec podpg-cls1-pg2 systemctl start patroni
podman exec podpg-cls1-pg3 systemctl start patroni
```

> Output:
```
'resume' request sent, waiting until it is recognized by all nodes
Success: cluster management is resumed
```

---

### Step 7 — Handle `start failed` State After pg_rewind

> ⚠ **This step is required after every `pg_rewind`.** Do not skip it.

After `pg_rewind`, PostgreSQL may enter `start failed` state with this error in the log:

```
FATAL: requested timeline 4 does not contain minimum recovery point 0/7006260 on timeline 3
```

**Why this happens:**

`pg_rewind` creates a `backup_label` that sets the minimum recovery point to `0/7006260` on TL3
(pg4's state). When PostgreSQL starts with `recovery_target_timeline = 'latest'`, it scans the
pgbackrest archive for history files. Because the old primary pushed `00000004.history` to the
archive AND left a local copy in its own `pg_wal/` directory, PostgreSQL finds TL4 as the
"latest" timeline. But TL4 diverged from TL3 at `0/7000000` — before the minimum recovery
point — so PostgreSQL correctly rejects it and crashes.

**Fix: remove the rogue TL4 history from two locations:**

#### 7a — Remove from the pgbackrest archive

Identify which archive the current stanza uses and remove the rogue TL4.history:

```bash
# Identify the active archive directory (highest 18-N)
podman exec podpg-cls1-pg4 bash -c \
  "find /var/lib/pgbackrest/archive/podpg-cls1 -name '*.history' | sort"
```

> Output:
```
/var/lib/pgbackrest/archive/podpg-cls1/18-5/00000004.history
```

Confirm the content is a rogue history (TL3 ends at the split-brain fork point):

```bash
podman exec podpg-cls1-pg4 \
  cat /var/lib/pgbackrest/archive/podpg-cls1/18-5/00000004.history
```

> Output:
```
1	0/6000000	no recovery target specified

2	0/70000A0	no recovery target specified

3	0/7000000	no recovery target specified
```

This is the rogue entry — TL3 is listed as ended at `0/7000000`, which is exactly the
split-brain divergence point. Compare to the correct TL3.history on pg4:

```bash
podman exec podpg-cls1-pg4 \
  cat /var/lib/pgbackrest/archive/podpg-cls1/18-5/00000003.history
```

> Output (correct — TL3 is the current timeline, no entry for it):
```
1	0/6000000	no recovery target specified

2	0/70000A0	no recovery target specified
```

Remove the rogue TL4.history and its associated WAL segments from the archive:

```bash
podman exec podpg-cls1-pg4 bash -c "
  rm -v /var/lib/pgbackrest/archive/podpg-cls1/18-5/00000004.history
  rm -rv /var/lib/pgbackrest/archive/podpg-cls1/18-5/0000000400000000
"
```

> Output:
```
removed '/var/lib/pgbackrest/archive/podpg-cls1/18-5/00000004.history'
removed '/var/lib/pgbackrest/archive/podpg-cls1/18-5/0000000400000000/000000040000000000000007-b23c843fb3067598a12a990523f32ac178667a95.lz4'
removed directory '/var/lib/pgbackrest/archive/podpg-cls1/18-5/0000000400000000'
```

#### 7b — Remove from each node's local `pg_wal/` directory

`pg_rewind` copies files from the source but does **not** purge old history files from the
local `pg_wal/` directory. The stale `00000004.history` created when the node ran as a TL4
primary is still present and must be removed manually:

```bash
for node in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $node ==="
  podman exec $node bash -c "ls /var/lib/postgresql/18/main/pg_wal/*.history"
  podman exec $node bash -c "rm -v /var/lib/postgresql/18/main/pg_wal/00000004.history"
  podman exec $node bash -c "ls /var/lib/postgresql/18/main/pg_wal/*.history"
done
```

> Output:
```
=== podpg-cls1-pg1 ===
/var/lib/postgresql/18/main/pg_wal/00000002.history
/var/lib/postgresql/18/main/pg_wal/00000003.history
/var/lib/postgresql/18/main/pg_wal/00000004.history   ← rogue
removed '/var/lib/postgresql/18/main/pg_wal/00000004.history'
/var/lib/postgresql/18/main/pg_wal/00000002.history
/var/lib/postgresql/18/main/pg_wal/00000003.history   ← only valid history remains

=== podpg-cls1-pg2 ===
... (same) ...

=== podpg-cls1-pg3 ===
... (same) ...
```

#### 7c — Restart Patroni on all old primary nodes

```bash
podman exec podpg-cls1-pg1 systemctl restart patroni
podman exec podpg-cls1-pg2 systemctl restart patroni
podman exec podpg-cls1-pg3 systemctl restart patroni
```

Wait ~20 seconds, then check:

```bash
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

> Output:
```
+ Cluster: podpg-cls1 (7649421311168285384) ----+-----------+----+-----------+------------------+
| Member         | Host        | Role           | State     | TL | Lag in MB | Tags             |
+----------------+-------------+----------------+-----------+----+-----------+------------------+
| podpg-cls1-pg1 | 172.18.0.11 | Standby Leader | streaming |  3 |           |                  |
| podpg-cls1-pg2 | 172.18.0.12 | Replica        | streaming |  3 |         0 |                  |
| podpg-cls1-pg3 | 172.18.0.13 | Replica        | streaming |  3 |         0 | nofailover: true |
+----------------+-------------+----------------+-----------+----+-----------+------------------+
```

✅ All nodes are streaming on TL3 (matching pg4).

---

### Step 7d — Fix New Primary (pg4) if it enters `start failed` After Restart

> ⚠ **This step is only needed if pg4 enters `start failed` state after a container or service
> restart following the DR promotion.** Check `patronictl list` on pg4 first — if it shows
> `Leader | running`, skip this step entirely.

After a service or container restart of pg4, Patroni may re-read its local `patroni.yml` and
find a `standby_cluster:` block in `bootstrap.dcs` that was generated when pg4 was originally
installed as the standby cluster. This causes Patroni to call `is_standby_cluster() = True`,
so it starts PostgreSQL in replica mode (creating `standby.signal`), which then fails because
pg4's checkpoint is ahead of the fork point where the rogue `00000004.history` branched.

The three root causes stack on each other:

| Cause | Effect |
|---|---|
| `standby_cluster:` in `bootstrap.dcs` of `/etc/patroni/patroni.yml` | Patroni starts as secondary → never acquires leader lock |
| `standby.signal` in data dir (created by Patroni in replica mode) | PostgreSQL starts in standby mode instead of primary mode |
| Local `pg_wal/00000004.history` still present | PostgreSQL resolves `latest` timeline as TL4, which is past pg4's checkpoint on TL3 → FATAL |

**Diagnose:**

```bash
# Confirm the issue: Patroni log shows "starting as a secondary" despite no lock owner
podman exec podpg-cls1-pg4 tail -5 /var/log/patroni/patroni.log

# Confirm standby_cluster is in local patroni.yml (NOT just the DCS config)
podman exec podpg-cls1-pg4 grep -n 'standby_cluster:' /etc/patroni/patroni.yml

# Confirm standby.signal exists
podman exec podpg-cls1-pg4 ls /var/lib/postgresql/18/main/standby.signal

# Confirm local rogue history exists
podman exec podpg-cls1-pg4 ls /var/lib/postgresql/18/main/pg_wal/00000004.history
```

**Fix:**

```bash
# 1 — Stop Patroni so it stops recreating standby.signal
podman exec podpg-cls1-pg4 systemctl stop patroni

# 2 — Remove standby_cluster block from bootstrap.dcs in patroni.yml
podman exec podpg-cls1-pg4 python3 - << 'EOF'
lines = open('/etc/patroni/patroni.yml').readlines()
out, skipping = [], False
for line in lines:
    if line.startswith('    standby_cluster:'):
        skipping = True
    elif skipping and not line.startswith('      ') and line.strip():
        skipping = False
    if not skipping:
        out.append(line)
open('/etc/patroni/patroni.yml', 'w').writelines(out)
print(f"Done — {len(out)} lines written")
EOF

# Verify standby_cluster is gone from patroni.yml
podman exec podpg-cls1-pg4 grep -n 'standby_cluster:' /etc/patroni/patroni.yml \
  && echo "WARNING: still present" || echo "OK: removed"

# 3 — Remove standby.signal so PostgreSQL starts as primary
podman exec podpg-cls1-pg4 rm -v /var/lib/postgresql/18/main/standby.signal

# 4 — Remove local rogue TL4 history file
podman exec podpg-cls1-pg4 rm -v /var/lib/postgresql/18/main/pg_wal/00000004.history

# 5 — Start Patroni
podman exec podpg-cls1-pg4 systemctl start patroni
sleep 15
podman exec podpg-cls1-pg4 patronictl list
```

> Expected output: pg4 shows `Leader | running` (pg4 may promote to the next timeline number
> as part of its first clean start — this is normal and does **not** indicate a new split brain).

**Also update `hosts.yml`** to reflect the post-DR topology so any future playbook run generates
the correct `patroni.yml` without `standby_cluster` for pg4:

```yaml
# After DR failover — pg4 is primary cluster, pg1/pg2/pg3 are standby cluster
primary_cluster:
  primary_cluster_leader:
    podpg-cls1-pg4:          # ← was standby_cluster_leader
      ip: "172.18.0.14"
      ansible_port: 2214

standby_cluster:
  standby_cluster_leader:
    podpg-cls1-pg1:          # ← was primary_cluster_leader
      ip: "172.18.0.11"
      ansible_port: 2211
      patroni_standby_cluster:
        host: "172.18.0.14"  # pg4's IP (new primary)
        port: 5432
  standby_cluster_replica:
    podpg-cls1-pg2: ...      # ← was primary_cluster_replica
    podpg-cls1-pg3: ...      # ← was primary_cluster_replica
```

**Why pg4 promotes to the next timeline on first start:**

After the failed replica-mode start attempts, if a `backup_label` was written to the data
directory, PostgreSQL enters a brief recovery pass on startup and then promotes — advancing
the timeline by one (e.g. TL3 → TL4). This is normal and harmless: the standby cluster
(pg1/pg2/pg3) will follow the new timeline automatically once they reconnect.

---

### Step 8 — Final Verification

```bash
echo "=== Old cluster (now standby) ==="
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list

echo ""
echo "=== New primary (pg4) ==="
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list

echo ""
echo "=== pg1 is in recovery (not writable) ==="
podman exec podpg-cls1-pg1 psql -U postgres -At -c \
  "SELECT pg_is_in_recovery() FROM pg_control_checkpoint();"
# ✅ Expected: t

echo ""
echo "=== standby_cluster_slot on pg4 is active ==="
podman exec podpg-cls1-pg4 psql -U postgres -c "
SELECT slot_name, slot_type, active, restart_lsn
FROM pg_replication_slots
WHERE slot_name = 'standby_cluster_slot';"
# ✅ Expected: active = t, restart_lsn non-null

echo ""
echo "=== Replication lag from pg4 to pg1 ==="
podman exec podpg-cls1-pg4 psql -U postgres -c "
SELECT application_name, state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) AS flush_lag_bytes,
       replay_lag
FROM pg_stat_replication
WHERE application_name = 'podpg-cls1-pg1';"
# ✅ Expected: state = streaming, flush_lag_bytes = 0
```

> Output from the 2026-06-09 resolution:
```
=== standby_cluster_slot on pg4 is active ===
     slot_name       | slot_type | active | restart_lsn
----------------------+-----------+--------+-------------
 standby_cluster_slot | physical  | t      | 0/700F4A8
(1 row)

=== Replication lag from pg4 to pg1 ===
 application_name |   state   | flush_lag_bytes | replay_lag
------------------+-----------+-----------------+------------
 podpg-cls1-pg1   | streaming |               0 |
(1 row)
```

---

### Step 9 — Restore Application Connection Limits

```bash
podman exec podpg-cls1-pg2 psql -U postgres -c \
  "ALTER DATABASE dba CONNECTION LIMIT -1;" 2>/dev/null || echo "(no dba db)"
```

---

## Critical Lesson: pg_rewind + Rogue Timeline History Files

When the split brain is resolved using `pg_rewind`, two sets of rogue timeline history files
**always** exist and **always** cause `start failed` unless manually removed:

| Location | File | Why it exists |
|---|---|---|
| pgbackrest archive (`18-5/`) | `00000004.history` | Old primary pushed it when it promoted to TL4 |
| Each node's `pg_wal/` dir | `00000004.history` | Local file from when node ran as TL4 primary |

`pg_rewind` does **not** clean up these files. After every split brain resolution via
`pg_rewind`, Step 7 (history file cleanup) is mandatory.

The specific error you will see if you skip Step 7:

```
FATAL: requested timeline 4 does not contain minimum recovery point 0/7006260 on timeline 3
DETAIL: The backup_label from pg_rewind requires ending on timeline 3, but
        the archive presents timeline 4 as the latest, which forked at 0/7000000
        — before the required minimum recovery end point.
```

---

## Quick Reference Decision Tree

```
Old primary comes back online after pg4 was promoted
       │
       ├─ Is pg1 cluster still in maintenance mode? ──yes──► Skip Step 1 (already fenced)
       │          no
       │           ↓
       │     FENCE IMMEDIATELY (Step 1)
       │
       ├─ Assess timeline (Step 2)
       │
       ├─ pg4 TL ≥ stale TL? ──yes──► pg_rewind (Steps 3-4) → standby_cluster config (Step 5)
       │                                → history file cleanup (Step 7) → verify (Step 8)
       │
       └─ pg4 TL < stale TL? ──yes──► pg_rewind still works! (same path)
            (true split brain)          Divergence point is on a common ancestor TL.
                                        ⚠ Writes on stale side after fork point are LOST.
                                        → history file cleanup (Step 7) is CRITICAL here.
```

> **Note:** `reinit` (wipe and reclone) is only needed if `pg_rewind` explicitly fails with
> an error such as "could not find common ancestor" or the data directories are corrupt beyond
> what pg_rewind can handle. In the 2026-06-09 incident, `pg_rewind` succeeded with the stale
> side on a **higher** timeline (TL4) than the new primary (TL3).