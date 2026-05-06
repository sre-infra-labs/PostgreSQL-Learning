# Physical Replication — Knowledge Base

> **Scope:** PostgreSQL physical (streaming) replication, with Patroni HA and pgBackRest WAL archiving.
> Covers WAL internals, replication topology, and which mechanism is used in each scenario.

---

## 1. The 4 Core Concepts

| Term | What it is | Where it lives |
|------|-----------|---------------|
| **WAL Record** | A single atomic change — e.g. "insert row X into page Y of table T". The smallest unit of WAL. | WAL buffer → WAL segment |
| **WAL Buffer** | Ring buffer in shared memory (`wal_buffers`). WAL records are written here first, before being flushed to disk. | RAM (shared memory) |
| **WAL Segment** | A 16 MB file on disk under `$PGDATA/pg_wal/` (e.g. `000000010000000000000001`). Contains many WAL records. Recycled after they are no longer needed. | Disk (`pg_wal/`) |
| **Archived WAL File** | A WAL segment copied to a remote/backup location via `archive_command` (S3, SMB, NFS, etc.). Used for PITR and archive recovery. | Remote storage |

**Key distinction:** Streaming replication sends **WAL records** (sub-segment granularity) over TCP in real time. Archived WAL files are full 16 MB segment files written asynchronously as a safety net.

---

## 2. How Streaming Replication Works (Step by Step)

```
PRIMARY
┌──────────────────────────────────────────────────────┐
│                                                      │
│  1. Transaction commits                              │
│         ↓                                            │
│  2. WAL Records written to WAL Buffer (shared mem)  │
│         ↓                                            │
│  3. WAL Writer flushes buffer → WAL Segment on disk │
│         ↓                                            │
│  4. WAL Sender process reads records immediately     │
│     (does NOT wait for segment to fill up)           │
│         │                                            │
└─────────┼────────────────────────────────────────────┘
          │  TCP connection (replication protocol)
          ▼
STANDBY
┌──────────────────────────────────────────────────────┐
│  5. WAL Receiver writes records to standby pg_wal/  │
│         ↓                                            │
│  6. Startup process replays records into data files  │
│     → standby is always nearly in sync              │
└──────────────────────────────────────────────────────┘
```

- The WAL Sender reads **records** as soon as they are flushed — not full segments.
- A busy primary can send hundreds of WAL records per second without waiting for a 16 MB segment to fill.
- The standby is always replaying from its current LSN (Log Sequence Number) forward.

---

## 3. Replication Topology — Patroni Multi-DC Cluster

```
DC1 — pg-cls2-prod                          DC2 — pg-cls2-dr
─────────────────────────────               ─────────────────────────────
pg-cls2-prod2  ← Leader (Primary)
   │
   │  WAL Sender ①  (sync streaming)
   ├──────────────────────────────► pg-cls2-prod0  (Sync Standby, DC1)
   │                                WAL Receiver → replays WAL records
   │
   │  WAL Sender ②  (async streaming)
   ├──────────────────────────────► pg-cls2-prod1  (Async Replica, DC1)
   │
   │  WAL Sender ③  (async streaming, cross-DC)
   ├──────────────────────────────► pg-cls2-dr1   (Standby Leader, DC2)
   │                                    │
   │                                    │  WAL Sender ④ (re-streams within DC2)
   │                                    ├──────────► pg-cls2-dr0  (Replica)
   │                                    └──────────► pg-cls2-dr2  (Replica)
   │
   │  archive_command  (async, fires after each WAL segment fills/rotates)
   └──────────────────────────────► SMB Share → .../pgbackrest_backups/archive/pg-cls2/
                                    (full 16 MB WAL segment files, .zst compressed)
```

### Key points

| # | What | Notes |
|---|------|-------|
| ① | Sync Standby | Primary waits for WAL record acknowledgment before returning commit to client. Zero data loss. |
| ②③④ | Async Replicas | Primary does not wait. Small replication lag possible. |
| Archive | SMB/S3 | Fires after each segment is complete. Not used for normal replication. |

---

## 4. Scenario Breakdown — Which Mechanism is Used When

### Scenario 1 — Normal Operation (healthy streaming)

**Mechanism: WAL records over TCP (streaming replication)**

```
Transaction commits on primary
  → WAL records written to WAL buffer
  → WAL writer flushes to WAL segment file on disk
  → WAL sender reads records immediately (sub-segment)
  → Sends over TCP to each standby's WAL receiver
  → Standby startup process replays records into data files
```

- Lag is sub-millisecond for sync standbys.
- The SMB/S3 archive is **not read at all** by standbys during normal operation.
- archive_command runs on the primary separately and writes full segment files to the archive.

---

### Scenario 2 — Standby Restarts / Short Outage (within WAL retention)

**Mechanism: WAL records via streaming, starting from saved LSN**

```
Standby was down for a few minutes
  → Reconnects to primary's WAL sender
  → Reports: "I need WAL from LSN 0/A1000000"
  → Primary checks: segment still in pg_wal/ (not yet recycled)
  → Streaming resumes — still WAL records, not files
```

- Works as long as `wal_keep_size` or a **replication slot** has preserved the needed segments.
- Replication slots prevent the primary from deleting WAL segments the standby still needs.

```sql
-- Check replication slots and retained WAL
SELECT slot_name, active, restart_lsn, pg_size_pretty(
         pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;
```

---

### Scenario 3 — Standby Too Far Behind (gap beyond `wal_keep_size`, no slot)

**Mechanism: Archive recovery — archived WAL segment files via `restore_command`**

```
Standby was down too long
  → Primary has already recycled the WAL segments it needs
  → WAL receiver gets error: "requested WAL segment not found"
  → Patroni triggers pg_basebackup OR pgBackRest restore
  → restore_command fetches archived WAL segment files from SMB/S3
  → Standby replays segment files (archive recovery) until it reaches
    the streaming range
  → Streaming replication takes over automatically
```

The `restore_command` in `postgresql.conf` / `recovery.conf`:
```
restore_command = 'pgbackrest --stanza=pg-cls2 archive-get %f "%p"'
```

This is also how the **Standby Cluster in DC2** catches up if it gets behind — it fetches
archived segments from the SMB share written by the DC1 primary.

---

### Scenario 4 — Leader Failover / Patroni Election

**Mechanism: Timeline history files from archive + streaming on new timeline**

```
Primary crashes (e.g., pg-cls2-prod2 goes down)
  → Patroni asks all replicas: "what is your received LSN?"
  → Replica with highest LSN wins election
  → New primary (e.g., pg-cls2-prod0) promotes itself
  → PostgreSQL increments timeline (TL 73 → TL 74)
  → New primary archives a timeline history file: 00000074.history
  → Other replicas use restore_command to fetch the .history file
  → They reattach to the new primary on TL 74 via streaming
```

```sql
-- Check timeline and LSN of all cluster members
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn
FROM pg_stat_replication;
```

```bash
# Patroni view of cluster after failover
patronictl -c /etc/patroni/patroni.yml list
```

---

### Scenario 5 — New Node Bootstrap / Re-init

**Mechanism: Physical base backup (data files) + then streaming WAL**

```
New standby joins, or Patroni reinit is triggered
  → Method A (pg_basebackup): copies all data files over TCP from primary
  → Method B (pgBackRest restore): fetches base backup from SMB archive
                                   + applies archived WAL to reach current LSN
  → After base backup is complete, switches to streaming replication
```

pgBackRest restore is faster when the backup is recent and the base backup is large,
because the network bandwidth for streaming from the live primary is shared with production traffic.

```bash
# pgBackRest restore (run as postgres user, PGDATA must be empty)
pgbackrest --stanza=pg-cls2 --delta restore

# Patroni-managed reinit (preferred — Patroni controls the timing)
patronictl -c /etc/patroni/patroni.yml reinit pg-cls2-prod pg-cls2-prod1 --force
```

---

### Scenario 6 — Standby Cluster Lag (cross-DC, DC2 behind DC1)

**Mechanism: Streaming replication (primary path), archive recovery (fallback)**

```
DC1 Primary → streams WAL records → DC2 Standby Leader (pg-cls2-dr1)
                                         ↓
                                  re-streams to DC2 replicas

If DC1→DC2 link is disrupted:
  DC2 Standby Leader switches to archive recovery
  → restore_command fetches archived WAL segments from SMB share
  → DC2 keeps replaying, just with higher lag
  → When DC1→DC2 link recovers, streaming resumes automatically
```

---

## 5. Summary Table

| Scenario | Mechanism | Archive (SMB/S3) involved? |
|----------|-----------|---------------------------|
| Normal replication | WAL records (TCP stream) | No — only written |
| Standby restart, within WAL retention | WAL records (streaming from saved LSN) | No |
| Standby too far behind | Archived WAL segment files (`restore_command`) | **Yes — read** |
| Failover / timeline switch | Timeline history file from archive + streaming | **Yes — read** |
| New node bootstrap | Base backup + WAL records (streaming) | Optionally read |
| Standby cluster (cross-DC) disruption | Archived WAL segment files (fallback) | **Yes — read** |
| Scheduled backup | WAL segment files copied to archive | **Yes — written** |

---

## 6. Replication States Reference

### 6.1 `state` column — pg_stat_replication (WAL sender state on primary)

| Value | Meaning |
|-------|---------|
| `startup` | WAL sender just started; handshake with standby in progress |
| `backup` | Standby is receiving a base backup (`pg_basebackup` in progress) |
| `catchup` | Standby has finished base backup and is replaying WAL to catch up to primary |
| `streaming` | ✅ Normal — standby is fully caught up and receiving WAL records in real time |

### 6.2 `sync_state` column — pg_stat_replication (synchrony mode)

| Value | Meaning |
|-------|---------|
| `async` | Standby is asynchronous — primary does not wait for it before committing |
| `potential` | Listed as a candidate sync standby but currently acting as async (because a higher-priority sync standby is active) |
| `sync` | ✅ Active synchronous standby — primary waits for this node's flush acknowledgment before returning commit to client |
| `quorum` | Part of a quorum-based sync group (`ANY N (node1, node2, ...)`) — N nodes in this group must acknowledge |

### 6.3 WAL Pipeline — What Each Lag Measures

```
Primary commits transaction
        │
        ▼
WAL written to primary's WAL buffer
        │
        ▼
WAL flushed to primary's disk  ◄─── this is the reference timestamp (t=0)
        │
        ├─── write_lag  ──► time until standby wrote WAL to its OS buffer (network RTT)
        │
        ├─── flush_lag  ──► time until standby flushed WAL to its disk
        │                   (for sync standbys: this is the commit overhead)
        │
        └─── replay_lag ──► time until standby replayed WAL into its data files
                            (how stale the replica's data actually is)
```

> **Rule of thumb:** `write_lag < flush_lag < replay_lag`. If `replay_lag` is high but `flush_lag`
> is low, the standby received the data but the startup process is slow to apply it.

### 6.4 Patroni Member States

| State | Where seen | Meaning |
|-------|-----------|---------|
| `running` | Leader only | PostgreSQL is up as primary (not in recovery) |
| `streaming` | Replica/Standby Leader | Replica is receiving WAL via streaming replication — fully caught up |
| `in archive recovery` | Replica/Standby Leader | Replica is replaying WAL from archive (SMB/S3); streaming not yet established or catching up via files |
| `catchup` | Replica | Replica finished base backup and is applying WAL to catch up to primary LSN |
| `starting` | Any | Patroni/PostgreSQL process is starting; not yet accepting connections |
| `initializing` | Any | Patroni is running `initdb` or `pg_basebackup` to set up data directory |
| `stopped` | Any | PostgreSQL process is not running on this node |
| `creating replica` | Replica | Patroni is actively cloning from primary via `pg_basebackup` |

### 6.5 pg_stat_wal_receiver `status` (on standby)

| Value | Meaning |
|-------|---------|
| `stopped` | WAL receiver process is not running |
| `starting` | WAL receiver connecting to primary |
| `streaming` | ✅ Receiving WAL records from primary WAL sender |
| `waiting` | Paused, waiting for next WAL segment |
| `restarting` | Reconnecting after a connection drop |
| `stopping` | WAL receiver shutting down |

---

## 7. Useful Monitoring Queries

```sql
-- ──────────────────────────────────────────────────────────────────────────────
-- Full replication lag report (run on PRIMARY)
-- write_lag  : primary flush → standby wrote WAL to OS buffer  (network RTT)
-- flush_lag  : primary flush → standby flushed WAL to disk     (sync commit overhead)
-- replay_lag : primary flush → standby applied WAL to data     (replica data staleness)
-- replication_lag_sec: replay_lag when active; 0 when idle and fully caught up
-- ──────────────────────────────────────────────────────────────────────────────
SELECT
    client_addr,
    application_name,
    state,          -- startup | backup | catchup | streaming
    sync_state,     -- async | potential | sync | quorum
    extract(epoch FROM write_lag)::numeric(10,3)  AS write_lag_sec,
    extract(epoch FROM flush_lag)::numeric(10,3)  AS flush_lag_sec,
    extract(epoch FROM replay_lag)::numeric(10,3) AS replay_lag_sec,
    COALESCE(
        extract(epoch FROM replay_lag)::numeric(10,3),
        CASE WHEN sent_lsn = replay_lsn THEN 0.000 END
    )                                             AS replication_lag_sec,
    round((sent_lsn - replay_lsn) / 1048576.0, 2) AS lag_mb
FROM pg_stat_replication
ORDER BY client_addr;

-- Standby receiver status (run on STANDBY)
SELECT
    status,                -- stopped | starting | streaming | waiting | restarting | stopping
    conninfo,
    receive_start_lsn,
    received_lsn,
    last_msg_send_time,
    last_msg_receipt_time,
    latest_end_lsn,
    latest_end_time,
    extract(epoch FROM (now() - last_msg_receipt_time))::numeric(10,3) AS secs_since_last_msg
FROM pg_stat_wal_receiver;

-- Standby recovery state (run on STANDBY)
SELECT
    pg_is_in_recovery()                           AS is_standby,
    pg_last_wal_receive_lsn()                     AS receive_lsn,
    pg_last_wal_replay_lsn()                      AS replay_lsn,
    extract(epoch FROM (now() - pg_last_xact_replay_timestamp()))
        ::numeric(10,3)                           AS replication_delay_sec,
    round(pg_wal_lsn_diff(
        pg_last_wal_receive_lsn(),
        pg_last_wal_replay_lsn()) / 1048576.0, 2) AS receive_vs_replay_lag_mb;

-- Replication slots — watch for WAL bloat in pg_wal/
SELECT slot_name, slot_type, active, restart_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots
ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) DESC;

-- Current WAL location on primary
SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());

-- WAL archiver health (run on PRIMARY)
SELECT archived_count, last_archived_wal, last_archived_time,
       failed_count,   last_failed_wal,   last_failed_time
FROM pg_stat_archiver;
```

---

## 8. Process Debug Commands

### 8.1 List All PostgreSQL Background Processes (OS level)

```bash
# Show all postgres processes with their roles
ps -eo pid,ppid,user,cmd | grep postgres | grep -v grep

# Wider view with cpu/mem
ps aux | grep postgres | grep -v grep

# Tree view — shows parent/child relationship clearly
ps axjf | grep -A 30 "postgres: checkpointer"

# Alternatively using pstree (if installed)
pstree -p $(pgrep -f "postgres -D") 2>/dev/null || \
  pstree -p $(systemctl show patroni -p MainPID --value) 2>/dev/null
```

### 8.2 PostgreSQL Process Reference

| Process name (in `ps` output) | Role | When present |
|-------------------------------|------|-------------|
| `postgres -D /var/lib/pgsql/...` | **Postmaster** — the parent of all postgres processes | Always (when PG is running) |
| `postgres: checkpointer` | Writes dirty shared_buffers pages to disk at checkpoints; also flushes WAL at checkpoint | Always |
| `postgres: background writer` | Proactively flushes dirty pages between checkpoints to reduce checkpoint I/O spikes | Always |
| `postgres: walwriter` | Flushes WAL buffer to WAL segment files on disk periodically | Always (primary) |
| `postgres: autovacuum launcher` | Wakes up autovacuum workers on a schedule | Always |
| `postgres: autovacuum worker` | Runs VACUUM / ANALYZE on individual tables | On demand |
| `postgres: wal sender ... streaming` | Streams WAL records to a specific standby replica | One per standby connected |
| `postgres: wal receiver` | Receives WAL records from primary (streaming) | On standby only |
| `postgres: startup recovering` | Applies WAL to standby data files (archive recovery or startup replay) | On standby, during recovery |
| `postgres: stats collector` | Collects activity stats for `pg_stat_*` views (PG < 15) | PG 14 and earlier |
| `postgres: logical replication launcher` | Manages logical replication workers | When `wal_level=logical` |
| `postgres: logical replication worker` | Applies logical replication changes from a publication | On subscriber |
| `postgres: <user> <db> <client_ip> idle` | Client backend — connected but idle | Per connection |
| `postgres: <user> <db> <client_ip> SELECT` | Client backend — actively running a query | Per active query |
| `postgres: <user> <db> <client_ip> idle in transaction` | Client backend — in an open transaction, not querying | ⚠️ Watch for lock bloat |

### 8.3 Find Specific Processes

```bash
# Postmaster PID
pgrep -f "postgres -D"
# or
systemctl show patroni -p MainPID --value

# WAL sender processes (one per connected standby)
ps aux | grep "wal sender" | grep -v grep

# WAL receiver process (on standby only)
ps aux | grep "wal receiver" | grep -v grep

# Startup / recovery process (on standby while replaying)
ps aux | grep "startup" | grep postgres | grep -v grep

# Checkpointer
ps aux | grep "checkpointer" | grep -v grep

# Background writer
ps aux | grep "background writer" | grep -v grep

# WAL writer
ps aux | grep "walwriter" | grep -v grep

# Autovacuum workers
ps aux | grep "autovacuum" | grep -v grep

# All processes sorted by CPU
ps aux --sort=-%cpu | grep postgres | grep -v grep | head -20

# Get PID of WAL receiver then inspect its open files (shows WAL segment being read)
WAL_RCV_PID=$(pgrep -f "wal receiver")
ls -la /proc/${WAL_RCV_PID}/fd 2>/dev/null | grep -i pg_wal
```

### 8.4 Correlate OS Processes with pg_stat_activity

```sql
-- Match OS PIDs to backend query / wait state
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,              -- idle | active | idle in transaction | idle in transaction (aborted) | fastpath function call | disabled
    wait_event_type,    -- Lock | LWLock | IO | BufferPin | Client | Extension | IPC | Timeout | Activity | NULL
    wait_event,
    left(query, 80) AS query
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
ORDER BY state, wait_event_type NULLS LAST;

-- Show only WAL sender and receiver backends
SELECT pid, usename, application_name, client_addr, state, wait_event_type, wait_event
FROM pg_stat_activity
WHERE backend_type IN ('walsender', 'walreceiver', 'startup');

-- All backend types present right now
SELECT backend_type, count(*)
FROM pg_stat_activity
GROUP BY backend_type
ORDER BY count DESC;
```

### 8.5 Ansible-based Process Check (multi-node cluster)

```bash
# Check WAL sender count on the primary
ansible pg-cls2-prod2 -i hosts__multi_datacenter.yml -u ansible -b \
  -m shell -a "ps aux | grep 'wal sender' | grep -v grep | wc -l"

# Check WAL receiver is running on each standby
ansible dc1,dc2 -i hosts__multi_datacenter.yml -u ansible -b \
  -m shell -a "ps aux | grep 'wal receiver' | grep -v grep"

# Check startup/recovery process on standbys
ansible dc1,dc2 -i hosts__multi_datacenter.yml -u ansible -b \
  -m shell -a "ps aux | grep 'startup' | grep postgres | grep -v grep"

# Quick process summary on all nodes
ansible all -i hosts__multi_datacenter.yml -u ansible -b \
  -m shell -a "ps aux | grep -E 'checkpointer|wal sender|wal receiver|walwriter|startup' \
               | grep postgres | grep -v grep"
```

---

## 9. WAL Buffer Internals

### 10.1 Single WAL Buffer Page Size

The WAL buffer is not one monolithic blob — it is a **circular ring buffer divided into fixed-size pages**.

| What | Size | How set |
|------|------|---------|
| **Single WAL buffer page** | **8 KB** (`XLOG_BLCKSZ`) | Compile-time constant — same as the data page size |
| **Total WAL buffer** | `wal_buffers` (default: auto = 1/32 of `shared_buffers`, min 64 KB, max 16 MB) | Runtime GUC in `postgresql.conf` |
| **Number of buffer slots** | `wal_buffers / XLOG_BLCKSZ` | Derived |

Example with `wal_buffers = 16MB`:
```
16 MB / 8 KB = 2048 WAL buffer pages (slots)
```

Each slot holds exactly one 8 KB WAL page. WAL records are packed into pages sequentially. A single WAL record can span multiple pages if it is larger than what remains on the current page.

### 10.2 WAL Page Layout

```
┌──────────────────────────────────────────────────────────┐  ← page boundary (8 KB aligned)
│  WAL Page Header (24 bytes standard / 40 bytes long)     │
│   xlp_magic     — sanity check magic number              │
│   xlp_info      — flags (LONG_HEADER, CONTRECORD, etc.)  │
│   xlp_tli       — timeline ID                            │
│   xlp_pageaddr  — LSN of the start of this page          │
│   xlp_rem_len   — bytes continued from previous page     │
├──────────────────────────────────────────────────────────┤
│  WAL Record 1  (variable size)                           │
│  WAL Record 2                                            │
│  WAL Record 3                                            │
│  ...                                                     │
├──────────────────────────────────────────────────────────┤
│  (possibly) partial WAL record — continues on next page  │
│  → next page header will have xlp_rem_len > 0            │
│    and XLP_FIRST_IS_CONTRECORD flag set                  │
├──────────────────────────────────────────────────────────┤
│  FREE SPACE  ← current write position (not yet full)     │
└──────────────────────────────────────────────────────────┘  ← 8 KB end
```

### 10.3 How Many Pages Are Flushed Per Operation?

**Only as many pages as needed to cover the target LSN** — not all pages, not always a full page.

`XLogFlush(LSN)` guarantees all WAL up to that LSN is durable. It flushes whatever pages are required — including the current partially filled page if the target LSN falls within it:

```
WAL buffer ring (circular, 2048 slots for 16MB wal_buffers):

 slot 0   | slot 1   | slot 2   | slot 3   | slot 4   | ... | slot 2047
[flushed] [flushed] [flushed] [PARTIAL ←] [ empty  ]       [ empty  ]
                                    ↑
                         current write position
                         flushed as-is when XLogFlush() targets any LSN within it
```

### 10.4 Can a Partially Full WAL Buffer Be Flushed?

**Yes — and it happens constantly.** Every synchronous commit flushes whatever is on the current partially-filled page. Here is every condition that triggers a partial page flush:

| # | Condition | Who calls flush | Partial page flushed? |
|---|-----------|----------------|----------------------|
| 1 | `synchronous_commit = on` (default) — transaction commit | Backend process | **Yes** — before returning COMMIT to client |
| 2 | `synchronous_commit = remote_write/remote_apply` | Backend process | **Yes** — locally first, then waits for standby ack |
| 3 | `synchronous_commit = off` — async commit | WAL writer (background) | **Yes** — within `wal_writer_delay` (default 200ms) |
| 4 | Checkpoint | Checkpointer process | **Yes** — all WAL up to checkpoint LSN |
| 5 | WAL buffer ring wrap-around | Backend or WAL writer | **Yes** — oldest dirty slot force-flushed before reuse |
| 6 | WAL Sender (streaming replication) | WAL sender process | **Yes** — if WAL not yet on disk, forces flush before sending |
| 7 | `pg_switch_wal()` called manually | Backend | **Yes** — flushes and rotates to a new segment |

### 10.5 Write vs Flush vs Sync — Three Levels

```
WAL Buffer (shared memory — RAM)
        │
        │  write() syscall
        │  — copies page from shared_memory to OS page cache
        │  — fast; survives process crash, NOT OS/power crash
        ▼
OS Page Cache (kernel RAM)
        │
        │  fsync() / fdatasync() / open_sync (per wal_sync_method)
        │  — forces kernel to flush to persistent storage
        │  — slow; survives OS crash and power loss
        ▼
Disk / SSD / persistent storage  ← durable WAL
```

`wal_sync_method` controls the fsync step:

| `wal_sync_method` | Mechanism | Notes |
|-------------------|-----------|-------|
| `fdatasync` | `fdatasync()` syscall | Default on Linux — flushes data, skips file metadata |
| `fsync` | `fsync()` syscall | Flushes data + metadata |
| `open_datasync` | `O_DSYNC` flag on `open()` | Each write is synchronous at OS level |
| `open_sync` | `O_SYNC` flag on `open()` | Full sync (data + metadata) on each write |
| `fsync_writethrough` | `fsync()` + bypass disk cache | macOS only |

### 10.6 WAL Writer Flush Batching (`wal_writer_flush_after`)

The WAL writer **writes** to the OS page cache frequently but only calls `fsync` after accumulating `wal_writer_flush_after` bytes (default **1 MB**):

```
WAL writer wakes every wal_writer_delay (default 200ms)
  → write() dirty WAL pages to OS page cache  (always — fast)
  → if accumulated unfsynced WAL >= wal_writer_flush_after (1MB):
      → fsync() / fdatasync()  (slow — real disk I/O)
  → else:
      → skip fsync (OS cache write only — not yet durable)
```

> **Important:** A synchronous commit (`synchronous_commit = on`) bypasses this batching and
> forces an immediate fsync regardless of `wal_writer_flush_after`.

### 10.7 Quick Reference

| Question | Answer |
|----------|--------|
| Single WAL buffer page size | **8 KB** (`XLOG_BLCKSZ`) — compile-time constant |
| Total WAL buffer | `wal_buffers` — default auto (~1/32 of `shared_buffers`) |
| Number of buffer slots | `wal_buffers / 8 KB` — e.g. 16 MB → 2048 slots |
| Pages flushed per operation | Only as many as needed to reach the target LSN |
| Can a partial page be flushed? | **Yes** — on every sync commit, checkpoint, WAL sender demand, buffer ring wrap, `pg_switch_wal()` |
| Async commit flush timing | WAL writer flushes partial page within `wal_writer_delay` (200ms) — not immediate |
| Fsync batching | `wal_writer_flush_after` (default 1 MB) — sync commits always bypass this |

---

## 10. Key Configuration Parameters

| Parameter | Role | Typical value |
|-----------|------|---------------|
| `wal_level` | Must be `replica` or `logical` for streaming | `replica` |
| `max_wal_senders` | Max concurrent WAL sender processes | `10` |
| `wal_keep_size` | MB of WAL to retain in `pg_wal/` for standbys without slots | `1024` (1 GB) |
| `wal_buffers` | Size of WAL buffer in shared memory | `64MB` |
| `archive_mode` | Enable WAL archiving | `on` |
| `archive_command` | Command to copy each completed WAL segment to archive | pgBackRest or cp |
| `restore_command` | Command standbys use to fetch archived WAL | pgBackRest archive-get |
| `synchronous_standby_names` | Names of sync standbys | `pg-cls2-prod0` |
| `synchronous_commit` | Durability vs latency: `on` waits for standby flush; `remote_write` waits for standby OS buffer only | `on` or `remote_write` |
| `recovery_target_timeline` | Which timeline to follow during recovery | `latest` |
| `hot_standby` | Allow read queries on standby | `on` |
| `wal_receiver_timeout` | How long WAL receiver waits before giving up and reconnecting | `60s` |
| `wal_sender_timeout` | How long WAL sender waits before declaring standby dead | `60s` |
