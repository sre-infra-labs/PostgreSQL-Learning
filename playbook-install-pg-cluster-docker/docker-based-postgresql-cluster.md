# Docker-Based PostgreSQL 18 HA Cluster
## Patroni + etcd + pgBackRest + pgBouncer + HAProxy + Keepalived + pg_exporter

---

## 📋 Table of Contents

### Core Documentation
1. [Quick Start (Docker)](#quick-start-docker)
2. [Architecture](#architecture)
3. [Component Stack](#component-stack)
4. [Mac Host One-Time Setup](#mac-host-one-time-setup)

### Connectivity & Management
5. [Connecting to PostgreSQL](#connecting-to-postgresql)
6. [Patroni Status & Management](#patroni-status--management)
7. [PostgreSQL Status](#postgresql-status)

### Component Operations
8. [HAProxy Status & Management](#haproxy-status--management)
9. [Keepalived Status & Management](#keepalived-status--management)
10. [pgBouncer Status & Management](#pgbouncer-status--management)
11. [etcd Status & Management](#etcd-status--management)
12. [pgBackRest Status & Management](#pgbackrest-status--management)

### Monitoring & Logs
13. [Log Inspection](#log-inspection)
14. [Health Validation Cheatsheet](#health-validation-cheatsheet)

### Failover & Disaster Recovery
15. [Failover Testing](#failover-testing)
16. [Disaster Recovery (DR) Testing: Complete Reference](#disaster-recovery-dr-testing-complete-reference)
   - [DR Quick Overview](#dr-quick-overview)
   - [DR Test Validation Matrix](#dr-test-validation-matrix)
   - [Pre-DR Baseline Verification](#pre-dr-baseline-verification)
   - [Disaster Scenario](#disaster-scenario)
   - [Manual Promotion](#manual-promotion)
   - [DR Mode Active](#dr-mode-active)
   - [Recovery Phase](#recovery-phase)
   - [Restore Topology](#restore-topology)
   - [Post-Recovery Validation](#post-recovery-validation)
   - [Understanding Timeline & LSN](#understanding-timeline--lsn)
   - [Replication Slots During DR](#replication-slots-during-dr)
   - [DR Troubleshooting](#dr-troubleshooting)
   - [Complete DR Test Verification Checklist](#complete-dr-test-verification-checklist)
   - [DR Test Execution Guide](#dr-test-execution-guide)

### Infrastructure & Deployment
17. [Troubleshooting](#troubleshooting)
18. [Common Ansible Operations](#common-ansible-operations)
19. [Prometheus Scrape Config](#prometheus-scrape-config)
20. [Design Notes](#design-notes)
21. [Other Miscellaneous Commands](#other-miscellaneous-commands)

---

## Quick Start (Docker)

This setup uses **Docker** on macOS with a shared `lab-network` for all containers.

```bash
cd playbook-install-pg-cluster-docker/

# Phase 1: Create Docker containers and network
ansible-playbook playbook-setup-docker.yml

# Phase 2: Install PostgreSQL 18 cluster
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml --vault-password-file=vault-pass

# Verify cluster status
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

---

## Architecture

Every pg container runs the full stack — PostgreSQL, Patroni, etcd, pgBouncer, HAProxy, and
Keepalived — in a single privileged container. There is no separate proxy or DCS container.

```
Host (macOS)
│
├── Docker Network: lab-network (172.18.0.0/16)
│   │
│   ├── 172.18.0.9  ← Keepalived Replica VIP  (floats to the sync standby; /synchronous endpoint)
│   ├── 172.18.0.10 ← Keepalived Primary VIP  (floats to the Patroni leader)
│   │
│   ├── pg1  (172.18.0.11)  — Leader or Sync Standby  (designed: Leader)
│   ├── pg2  (172.18.0.12)  — Leader or Sync Standby  (designed: Sync Standby)
│   └── pg3  (172.18.0.13)  — Replica                 (nosync: true — never elected Sync Standby or Leader)
│
└── Docker Named Volume: pg-backups  (shared pgBackRest POSIX repo)
```

### Replication Topology

| Node | Designed Role   | Patroni Tag     | Notes                                    |
|------|-----------------|-----------------|------------------------------------------|
| pg1  | Leader          | —               | Primary; writes committed only after pg2 acks WAL |
| pg2  | Sync Standby    | —               | `synchronous_node_count=1`; zero data loss on pg1 failure |
| pg3  | Replica         | `nosync: true`  | Always async; never elected Sync Standby |

Roles are dynamic — Patroni may promote pg2 or pg3 on failover. The designed topology is restored via
`patronictl switchover` after recovery. pg3 can become leader in a disaster but will never hold the
Sync Standby role.

### Port Mapping (host → container)

```
┌──────────┬──────┬──────┬─────────┬─────────────┬──────────┬───────────────────────────────────┐
│ Container│ SSH  │ PG   │ Patroni │ pg_exporter │ pgBouncer│ HAProxy (host ports — needs new    │
│          │      │      │ REST    │             │          │  container creation to take effect) │
├──────────┼──────┼──────┼─────────┼─────────────┼──────────┼────────┬──────────┬───────────────┤
│ pg1      │ 2221 │ 5433 │ 8011    │ 9194        │ 6433     │ 15000  │ 15001    │ 17000         │
│ pg2      │ 2222 │ 5434 │ 8012    │ 9195        │ 6434     │ 25000  │ 25001    │ 27000         │
│ pg3      │ 2223 │ 5435 │ 8013    │ 9196        │ 6435     │ 35000  │ 35001    │ 37000         │
└──────────┴──────┴──────┴─────────┴─────────────┴──────────┴────────┴──────────┴───────────────┘
                                                              write    read      stats
                                                              port     port      UI

HAProxy container-internal ports (always available via docker exec):
  :5000 → write   (routes to Patroni primary only, health: GET /primary  → 200)
  :5001 → read    (routes to healthy replicas,     health: GET /replica  → 200)
  :7000 → stats   (HTTP UI, basic auth: admin / <PG_SUPERUSER_PWD>)

etcd cluster (inter-container, no host port mapping needed):
  pg1: 172.18.0.11:2379 (client) / :2380 (peer)
  pg2: 172.18.0.12:2379 (client) / :2380 (peer)
  pg3: 172.18.0.13:2379 (client) / :2380 (peer)
```

### Traffic Flow

```
Application write  →  VIP 172.18.0.10:5000  →  HAProxy (any node)  →  <leader> :5432
Application read   →  VIP 172.18.0.9:5001   →  HAProxy (any node)  →  <replica> :5432

Notes:
  - Any node's HAProxy correctly routes writes to the leader and reads to replicas,
    so both VIPs work for both ports. The replica VIP (172.18.0.9) is the preferred
    read endpoint because it floats away from a node that loses its replica status.
  - VIPs are inside the Docker network. From Mac, use HAProxy host-mapped ports instead
    (localhost:15000 / 25000 / 35000 for writes; :15001 / 25001 / 35001 for reads).

After failover (e.g. pg2 promoted to leader after pg1 failure):
  Keepalived detects /primary passes on pg2 → primary VIP (172.18.0.10) migrates to pg2
  HAProxy health checks catch up within 6–9 s (3 × inter=3s)
  pg3 (nosync) becomes the only remaining replica; restore pg1 and switchover back when ready
```

---

## Component Stack

| Component        | Version   | Role                                             |
|------------------|-----------|--------------------------------------------------|
| PostgreSQL       | 18 (PGDG) | Database engine                                  |
| Patroni          | 4.0.6     | HADR orchestration (automatic failover)          |
| etcd             | 3.5.17    | DCS — distributed configuration store           |
| pgBackRest       | latest    | Backup & restore (POSIX shared volume)           |
| pgBouncer        | latest    | Connection pooler per node                       |
| HAProxy          | 2.8.x     | TCP proxy with Patroni API health checks         |
| Keepalived       | 2.2.x     | VRRP VIP management (unicast, no multicast)      |
| pg_exporter      | 0.17.1    | Prometheus metrics                               |
| pg_wait_tracer   | main      | Wait event tracing (compiled from source)        |

---

## Mac Host One-Time Setup

Run these steps once on your Mac to enable password-free named connections and connection pooling.

### 1. /etc/hosts — hostname aliases

```bash
sudo tee -a /etc/hosts << 'EOF'

# PostgreSQL Docker cluster — lab-network 172.18.0.0/16
127.0.0.1  pg1    # PostgreSQL :5433  pgBouncer :6433  Patroni :8011
127.0.0.1  pg2    # PostgreSQL :5434  pgBouncer :6434  Patroni :8012
127.0.0.1  pg3    # PostgreSQL :5435  pgBouncer :6435  Patroni :8013
EOF
```

Verify: `ping -c1 pg1` should resolve to `127.0.0.1`.

### 2. ~/.pgpass — password file

File: `~/.pgpass` (permissions must be `chmod 600`)

```
pg1:*:*:*:Pg@Lab2026!
pg2:*:*:*:Pg@Lab2026!
pg3:*:*:*:Pg@Lab2026!
127.0.0.1:*:*:*:Pg@Lab2026!
localhost:*:*:*:Pg@Lab2026!
```

Wildcard entries cover all ports, databases, and users on each hostname.
`PGPASSWORD` env var takes precedence over `.pgpass`; keep them in sync in `~/.vars_personal`.

### 3. ~/.pg_service.conf — named services

File: `~/.pg_service.conf` — connect with `psql service=<name>` or `PGSERVICE=<name>`.

```ini
[pg1]           host=pg1  port=5433  user=postgres  dbname=postgres
[pg2]           host=pg2  port=5434  user=postgres  dbname=postgres
[pg3]           host=pg3  port=5435  user=postgres  dbname=postgres

[pg1-bouncer]   host=pg1  port=6433  user=postgres  dbname=postgres
[pg2-bouncer]   host=pg2  port=6434  user=postgres  dbname=postgres
[pg3-bouncer]   host=pg3  port=6435  user=postgres  dbname=postgres

[pg1-rw]        host=pg1  port=5433  user=dba_rw    dbname=dba
[pg2-rw]        host=pg2  port=5434  user=dba_rw    dbname=dba
[pg3-rw]        host=pg3  port=5435  user=dba_rw    dbname=dba

[pg1-ro]        host=pg1  port=5433  user=dba_ro    dbname=dba
[pg2-ro]        host=pg2  port=5434  user=dba_ro    dbname=dba
[pg3-ro]        host=pg3  port=5435  user=dba_ro    dbname=dba
```

### 4. ~/.zshrc — dynamic shell functions

Add to `~/.zshrc` (already done if you followed the setup steps):

```zsh
_PG_NODES=("8011:pg1:5433" "8012:pg2:5434" "8013:pg3:5435")

# Connect to current Patroni primary — accepts any extra psql args
function pg-primary() {
  for _entry in "${_PG_NODES[@]}"; do
    local _pp="${_entry%%:*}" _rest="${_entry#*:}"
    local _h="${_rest%%:*}"   _p="${_rest##*:}"
    if curl -sf --max-time 2 "http://localhost:${_pp}/primary" >/dev/null 2>&1; then
      echo "[pg-primary -> ${_h}:${_p}]"; psql -h "${_h}" -p "${_p}" -U postgres "$@"; return $?
    fi
  done; echo "ERROR: no primary found" >&2; return 1
}

# Connect to first available healthy replica
function pg-replica() {
  for _entry in "${_PG_NODES[@]}"; do
    local _pp="${_entry%%:*}" _rest="${_entry#*:}"
    local _h="${_rest%%:*}"   _p="${_rest##*:}"
    if curl -sf --max-time 2 "http://localhost:${_pp}/replica" >/dev/null 2>&1; then
      echo "[pg-replica -> ${_h}:${_p}]"; psql -h "${_h}" -p "${_p}" -U postgres "$@"; return $?
    fi
  done; echo "ERROR: no replica found" >&2; return 1
}

# Print Patroni cluster state, Keepalived VIPs, and HAProxy backend health
function pg-status() {
  echo "=== Patroni cluster ==="
  docker exec pg1 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null \
    || docker exec pg2 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null \
    || echo "ERROR: containers not reachable"

  echo ""
  echo "=== Keepalived VIPs ==="
  for _n in pg1 pg2 pg3; do
    docker exec "${_n}" ip addr show eth0 2>/dev/null \
      | awk -v node="${_n}" '/inet / && !/172\.18\.0\.1[123]\//{printf "  %-4s <- %s\n", node, $2}'
  done

  echo ""
  echo "=== HAProxy backends (be_write / be_read) ==="
  for _n in pg1 pg2 pg3; do
    if docker exec "${_n}" systemctl is-active haproxy >/dev/null 2>&1; then
      docker exec "${_n}" bash -c \
        'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
         | grep -v "^#\|FRONTEND\|stats" | cut -d, -f1,2,18' 2>/dev/null
      break
    fi
  done
}

alias psql-pg1='psql service=pg1'
alias psql-pg2='psql service=pg2'
alias psql-pg3='psql service=pg3'
```

### 5. ~/.vars_personal — PGPASSWORD

```bash
export PGPWD_PERSONAL='Pg@Lab2026!'
export PGPASSWORD=$PGPWD_PERSONAL
```

---

## Connecting to PostgreSQL

### A. By hostname — direct PG (after /etc/hosts is set)

```bash
# No password prompt — resolved via ~/.pgpass
psql -h pg1 -p 5433 -U postgres postgres    # leader
psql -h pg2 -p 5434 -U postgres postgres    # sync standby
psql -h pg3 -p 5435 -U postgres postgres    # replica (nosync)
```

### B. By hostname — pgBouncer (after /etc/hosts is set)

```bash
psql -h pg1 -p 6433 -U postgres postgres
psql -h pg2 -p 6434 -U postgres postgres
psql -h pg3 -p 6435 -U postgres postgres
```

### C. Named service (after /etc/hosts is set)

```bash
psql service=pg1            # direct PG on pg1
psql service=pg2            # direct PG on pg2  (sync standby)
psql service=pg3            # direct PG on pg3
psql service=pg1-bouncer    # via pgBouncer on pg1
psql service=pg1-rw         # as dba_rw on pg1
psql service=pg1-ro         # as dba_ro on pg1
```

### D. Dynamic shell functions — role-based (after /etc/hosts is set)

These query Patroni REST API on ports 8011/8012/8013 to find the current role automatically.
No need to know which container is currently the leader.

```bash
pg-primary                                          # open psql on current leader
pg-primary -c "SELECT pg_is_in_recovery();"         # run query on leader
pg-primary -d dba -c "SELECT count(*) FROM ..."     # specific database

pg-replica                                          # open psql on first healthy replica
pg-replica -c "SELECT pg_last_wal_replay_lsn();"   # check replica lag

pg-status                                           # cluster overview (Patroni + VIPs + HAProxy)
```

### E. Via Keepalived VIPs (Docker-internal — from container exec)

The VIPs float between containers. Accessible inside the Docker network (not from Mac host directly).

```bash
# Primary VIP (172.18.0.10) — always the Patroni leader
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5432 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# Replica VIP (172.18.0.9) — highest-priority healthy replica
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.9 -p 5432 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
```

### F. Via HAProxy + VIP (Docker-internal — best practice for applications)

HAProxy routes based on Patroni health check — write port goes only to primary,
read port goes only to replicas, regardless of which container's HAProxy you hit.

```bash
# Writes via primary VIP + HAProxy write port
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
# → always returns the primary node, is_replica=f

# Reads via primary VIP + HAProxy read port
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5001 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
# → always returns a replica, is_replica=t

# Reads via replica VIP + HAProxy read port
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.9 -p 5001 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
```

### G. Via HAProxy host-mapped ports (from Mac host — after container recreation)

HAProxy ports are exposed to the Mac host via per-container port mappings.
These require the containers to be recreated (see Ansible Operations below).

```bash
# Write port on each node's HAProxy — all route to the current primary
psql -h localhost -p 15000 -U postgres postgres   # pg1 HAProxy write  ← usually primary
psql -h localhost -p 25000 -U postgres postgres   # pg2 HAProxy write
psql -h localhost -p 35000 -U postgres postgres   # pg3 HAProxy write

# Read port on each node's HAProxy — all route to a healthy replica
psql -h localhost -p 15001 -U postgres postgres   # pg1 HAProxy read
psql -h localhost -p 25001 -U postgres postgres   # pg2 HAProxy read
psql -h localhost -p 35001 -U postgres postgres   # pg3 HAProxy read

# HAProxy stats page (open in browser)
open http://localhost:17000    # pg1 stats  (admin / Pg@Lab2026!)
open http://localhost:27000    # pg2 stats
open http://localhost:37000    # pg3 stats

# Using hostname aliases (after /etc/hosts)
psql -h pg1 -p 15000 -U postgres postgres   # HAProxy write via pg1
psql -h pg2 -p 25001 -U postgres postgres   # HAProxy read  via pg2
```

---

## Patroni Status & Management

```bash
# Full cluster status (run from any node)
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list

# Cluster topology with history
docker exec pg2 patronictl -c /etc/patroni/patroni.yml topology

# Cluster event history (switchovers, failovers, timeline changes)
docker exec pg2 patronictl -c /etc/patroni/patroni.yml history pg-docker-cls1

# Replication lag check
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list | grep -E "Lag|Member"

# Show current cluster config (DCS-stored parameters)
docker exec pg2 patronictl -c /etc/patroni/patroni.yml show-config

# Edit DCS-stored cluster config
docker exec pg2 patronictl -c /etc/patroni/patroni.yml edit-config

# Patroni REST API — health check on each node
curl -s http://localhost:8011/patroni | python3 -m json.tool   # pg1
curl -s http://localhost:8012/patroni | python3 -m json.tool   # pg2
curl -s http://localhost:8013/patroni | python3 -m json.tool   # pg3

# Check which node is primary (returns HTTP 200 only on primary, 503 otherwise)
curl -s -o /dev/null -w "%{http_code}" http://localhost:8011/primary   # pg1
curl -s -o /dev/null -w "%{http_code}" http://localhost:8012/primary   # pg2
curl -s -o /dev/null -w "%{http_code}" http://localhost:8013/primary   # pg3 (never primary)

# Check which nodes are healthy replicas
curl -s -o /dev/null -w "%{http_code}" http://localhost:8011/replica   # 200 if streaming replica
curl -s -o /dev/null -w "%{http_code}" http://localhost:8013/replica   # 200 if streaming replica

# Switchover (graceful, requires a leader)
# IMPORTANT: cluster name is a required positional argument; omitting it triggers interactive
# mode which aborts with "Aborted!" when Enter is pressed with no input.
# --force suppresses the interactive confirmation prompt.
# --leader  = current primary to step down  (check with: patronictl list)
# --candidate = replica to promote; either pg1 or pg2 can be leader — pick the other one
# Example (replace <current-leader> and <candidate> with actual node names):
docker exec pg1 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader <current-leader> --candidate <candidate> --force

# Trigger a manual failover (promotes a replica to leader)
docker exec pg2 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force

# Failover to a specific node
# NOTE: Patroni 4.x uses --leader instead of the deprecated --master flag
docker exec pg2 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 \
  --leader pg2 --candidate pg1 --force

# Pause/resume Patroni automatic failover
docker exec pg2 patronictl -c /etc/patroni/patroni.yml pause
docker exec pg2 patronictl -c /etc/patroni/patroni.yml resume

# Reload Patroni config after editing patroni.yml
docker exec pg2 patronictl -c /etc/patroni/patroni.yml reload pg-docker-cls1

# Reinitialize a lagging/diverged replica
docker exec pg2 patronictl -c /etc/patroni/patroni.yml reinit pg-docker-cls1 pg1 --force
```

---

## PostgreSQL Status

```bash
export PGPASSWORD='Pg@Lab2026!'

# Connect to specific node (pg1 or pg2 may be leader at any time; use pg-primary for role-based access)
psql -h localhost -p 5433 -U postgres postgres   # pg1
psql -h localhost -p 5434 -U postgres postgres   # pg2
psql -h localhost -p 5435 -U postgres postgres   # pg3 (always replica)

# Replication status — lag in seconds and bytes (run on primary — pg1)
# write_lag  : primary flush → standby wrote WAL to OS buffer  (network RTT)
# flush_lag  : primary flush → standby flushed WAL to disk     (commit overhead for sync standby)
# replay_lag : primary flush → standby applied WAL to data     (replica data staleness)
# replication_lag_sec: replay_lag when active; 0 when idle and fully caught up (lag_mb=0)
psql -h localhost -p 5433 -U postgres postgres -c "
  SELECT client_addr,
         application_name,
         state,
         sync_state,
         extract(epoch FROM write_lag)::numeric(10,3)  AS write_lag_sec,
         extract(epoch FROM flush_lag)::numeric(10,3)  AS flush_lag_sec,
         extract(epoch FROM replay_lag)::numeric(10,3) AS replay_lag_sec,
         COALESCE(
           extract(epoch FROM replay_lag)::numeric(10,3),
           CASE WHEN sent_lsn = replay_lsn THEN 0.000 END
         )                                             AS replication_lag_sec,
         round((sent_lsn - replay_lsn) / 1048576.0, 2) AS lag_mb
  FROM pg_stat_replication
  ORDER BY client_addr;"

# Check standby recovery status (run on replica — pg2 or pg3)
# replication_delay: seconds since last transaction was replayed on this replica
psql -h localhost -p 5434 -U postgres postgres -c "
  SELECT pg_is_in_recovery(),
         extract(epoch FROM (now() - pg_last_xact_replay_timestamp()))::numeric(10,3) AS replication_delay_sec,
         pg_last_wal_receive_lsn(),
         pg_last_wal_replay_lsn(),
         round((pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())) / 1048576.0, 2) AS receive_vs_replay_lag_mb;"

# Active connections and sessions (run on primary — pg1)
psql -h localhost -p 5433 -U postgres postgres -c "
  SELECT count(*), state, wait_event_type, wait_event
  FROM pg_stat_activity GROUP BY state, wait_event_type, wait_event ORDER BY count DESC;"

# Long-running queries (>30s) (run on primary — pg1)
psql -h localhost -p 5433 -U postgres postgres -c "
  SELECT pid, now()-query_start AS duration, state, left(query,80) AS query
  FROM pg_stat_activity
  WHERE state != 'idle' AND query_start < now() - interval '30 seconds'
  ORDER BY duration DESC;"

# pg_stat_statements top 10 by total time (run on primary — pg1)
psql -h localhost -p 5433 -U postgres postgres -c "
  SELECT round(total_exec_time::numeric,2) AS total_ms,
         calls, round(mean_exec_time::numeric,2) AS mean_ms,
         left(query,80) AS query
  FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;"

# Database sizes
psql -h localhost -p 5433 -U postgres postgres -c "
  SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY 2 DESC;"

# Table bloat (top 10)
psql -h localhost -p 5433 -U postgres postgres -c "
  SELECT schemaname, tablename,
         pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
         n_dead_tup, n_live_tup
  FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10;"
```

---

## HAProxy Status & Management

```bash
# HAProxy backend health summary (CSV stats from inside a container)
docker exec pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep -v "^#" | cut -d, -f1,2,18 \
   | awk -F, '"'"'{printf "%-12s %-8s %s\n", $1, $2, $3}'"'"''

# Full stats page (open in browser after port-forwarding)
# From inside container: http://172.18.0.12:7000/  (admin / <PG_SUPERUSER_PWD>)

# Check which backends are UP (for write port)
docker exec pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep "be_write" | cut -d, -f1,2,18 \
   | awk -F, '"'"'{printf "%-12s %-8s %s\n", $1, $2, $3}'"'"''

# Check which backends are UP (for read port)
docker exec pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep "be_read" | cut -d, -f1,2,18 \
   | awk -F, '"'"'{printf "%-12s %-8s %s\n", $1, $2, $3}'"'"''

# HAProxy service status on each node
for n in pg1 pg2 pg3; do
  echo "=== $n ==="; docker exec $n systemctl status haproxy --no-pager -l | tail -3
done

# Reload HAProxy config (no connection drops, used after config change)
for n in pg1 pg2 pg3; do docker exec $n systemctl reload haproxy; done

# Verify HAProxy write port routes only to primary
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres -d postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# Verify HAProxy read port routes only to replica
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5001 \
  -U postgres -d postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
```

---

## Keepalived Status & Management

```bash
# Which node holds each VIP
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n ip addr show eth0 | grep "inet "
done
# 172.18.0.10 (eth0:vip)    → Patroni primary (leader)
# 172.18.0.9  (eth0:rvip)   → sync standby (Keepalived uses /synchronous endpoint)

# Keepalived service status
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n systemctl status keepalived --no-pager | tail -5
done

# VRRP state on each node (MASTER vs BACKUP)
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  docker exec $n journalctl -u keepalived --no-pager -n 5 2>/dev/null \
    | grep -E "MASTER|BACKUP" | tail -2
done

# Keepalived effective priorities (shows weight contribution)
for n in pg1 pg2 pg3; do
  echo -n "$n primary check: "
  docker exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary
  echo -n "  replica check: "
  docker exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/replica
  echo
done

# Manually verify VIP reachability from inside cluster
docker exec pg3 ping -c 2 172.18.0.10   # primary VIP
docker exec pg3 ping -c 2 172.18.0.9    # replica VIP

# Restart Keepalived (re-triggers VRRP election)
for n in pg1 pg2 pg3; do docker exec $n systemctl restart keepalived; done
# Wait ~8s for election to settle then re-check VIP assignment
```

---

## pgBouncer Status & Management

```bash
# pgBouncer admin console (from Mac host via mapped port)
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -p 6433 -U postgres pgbouncer -c "SHOW POOLS;"    # pg1
psql -h localhost -p 6434 -U postgres pgbouncer -c "SHOW POOLS;"    # pg2
psql -h localhost -p 6435 -U postgres pgbouncer -c "SHOW POOLS;"    # pg3

# All useful pgBouncer admin commands
psql -h localhost -p 6434 -U postgres pgbouncer << 'EOF'
SHOW CLIENTS;
SHOW SERVERS;
SHOW STATS;
SHOW POOLS;
SHOW DATABASES;
SHOW CONFIG;
EOF

# pgBouncer service status
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n systemctl status pgbouncer --no-pager | tail -3
done

# Reload pgBouncer after config change
for n in pg1 pg2 pg3; do docker exec $n systemctl reload pgbouncer; done

# Fix stale connection pool (SASL auth failures after failover)
# This clears all server-side connections and forces reconnects
for n in pg1 pg2 pg3; do
  echo "Reconnecting $n pgBouncer pools..."
  docker exec $n bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 127.0.0.1 -p 6432 \
    -U postgres pgbouncer -c "RECONNECT;" 2>/dev/null' \
  || docker exec $n systemctl reload pgbouncer
done

# Check which PostgreSQL host each pgBouncer is pointing to
for n in pg1 pg2 pg3; do
  echo -n "$n pgbouncer → " && docker exec $n grep "^*" /etc/pgbouncer/pgbouncer.ini
done
```

---

## etcd Status & Management

```bash
# etcd cluster member list (from inside container)
docker exec pg1 etcdctl --endpoints=http://172.18.0.11:2379 member list

# etcd cluster health
docker exec pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health

# etcd endpoint status (leader, raft term, raft index)
docker exec pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint status --write-out=table

# Read Patroni DCS key
docker exec pg1 etcdctl --endpoints=http://172.18.0.11:2379 \
  get /service/pg-docker-cls1/leader

# etcd service status
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n systemctl status etcd --no-pager | tail -3
done
```

---

## pgBackRest Status & Management

```bash
# Show backup info (run from any node with access to shared volume)
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 info

# Full backup (run on leader — pg1)
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info backup --type=full

# Incremental backup
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info backup --type=incr

# Differential backup
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info backup --type=diff

# Check backup integrity
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 check

# Restore (stop patroni first, then restore, then restart)
docker exec pg1 systemctl stop patroni
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info restore --delta
docker exec pg1 systemctl start patroni

# Point-in-time restore
docker exec pg1 systemctl stop patroni
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info restore --delta \
  --target="2026-04-30 10:30:00" --target-action=promote
docker exec pg1 systemctl start patroni
```

---

## Log Inspection

All commands use `docker exec` so they work from the Mac host terminal without SSH.

### PostgreSQL logs

```bash
# Tail PostgreSQL log on the current leader (pg1)
docker exec pg1 tail -100 /var/log/postgresql/postgresql-Wed.log

# Follow PostgreSQL log live
docker exec pg1 bash -c "tail -f /var/log/postgresql/postgresql-$(date +%a).log"

# Search for errors in PostgreSQL log
docker exec pg1 grep -i "ERROR\|FATAL\|PANIC" /var/log/postgresql/postgresql-Wed.log | tail -20

# PostgreSQL log on all nodes
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n bash -c \
    "tail -20 /var/log/postgresql/postgresql-\$(date +%a).log 2>/dev/null || echo 'no log'"
done
```

### Patroni logs

```bash
# Patroni log on all nodes
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n tail -30 /var/log/patroni/patroni.log
done

# Follow Patroni log live on leader
docker exec pg1 tail -f /var/log/patroni/patroni.log

# Patroni log via journald
docker exec pg1 journalctl -u patroni --no-pager -n 50

# Search for failover/switchover events
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n grep -i "promoting\|demoting\|failover\|switchover\|leader" \
    /var/log/patroni/patroni.log | tail -10
done
```

### HAProxy logs

```bash
# HAProxy logs via journald
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u haproxy --no-pager -n 20
done

# Follow HAProxy log live
docker exec pg1 journalctl -u haproxy -f

# Check backend state changes in HAProxy log
docker exec pg1 journalctl -u haproxy --no-pager | grep -i "UP\|DOWN\|BACKEND"
```

### Keepalived logs

```bash
# Keepalived VRRP election and VIP assignment events
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u keepalived --no-pager -n 20
done

# Follow Keepalived log live (watch VIP migrations)
docker exec pg1 journalctl -u keepalived -f

# Show only MASTER/BACKUP transitions
for n in pg1 pg2 pg3; do
  echo -n "$n: " && docker exec $n journalctl -u keepalived --no-pager \
    | grep -E "MASTER STATE|BACKUP STATE" | tail -3
done
```

### pgBouncer logs

```bash
# pgBouncer log on all nodes
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n tail -20 /var/log/pgbouncer/pgbouncer.log
done

# Follow pgBouncer log live
docker exec pg1 tail -f /var/log/pgbouncer/pgbouncer.log

# Search for auth errors
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n grep -i "ERROR\|failed\|refused" \
    /var/log/pgbouncer/pgbouncer.log | tail -5
done
```

### pgBackRest logs

```bash
# pgBackRest backup log
docker exec pg1 cat /var/log/pgbackrest/pg-docker-cls1-backup.log 2>/dev/null | tail -30

# List all pgBackRest logs
docker exec pg1 ls /var/log/pgbackrest/

# Check stanza status and health
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 info
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 check

# Check stanza details (system-id, wal_system_identifier, etc.)
docker exec pg1 sudo -u postgres pgbackrest --stanza=pg-docker-cls1 info --log-level-console=info
```

### etcd logs

```bash
# etcd logs via journald
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u etcd --no-pager -n 15
done

# etcd leader election events
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u etcd --no-pager \
    | grep -i "elected\|leader\|follower" | tail -5
done
```

---

## Health Validation Cheatsheet

```bash
export PGPASSWORD='Pg@Lab2026!'

# 1. Patroni cluster state
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list

# 2. VIP locations
for n in pg1 pg2 pg3; do
  echo -n "$n: " && docker exec $n ip addr show eth0 | grep "inet " | awk '{print $2}'
done

# 3. HAProxy backend health (1 line per backend)
docker exec pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep -v "^#\|FRONTEND" | cut -d, -f1,2,18'

# 4. Write path: confirm connection lands on primary
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# 5. Read path: confirm connection lands on a replica
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5001 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# 6. All direct PG ports
for port in 5433 5434 5435; do
  echo -n "localhost:$port → "
  psql -h localhost -p $port -U postgres postgres -c "SELECT pg_is_in_recovery();" -t 2>&1 | tr -d ' \n'
  echo
done

# 7. All pgBouncer ports
for port in 6433 6434 6435; do
  echo -n "localhost:$port → "
  psql -h localhost -p $port -U postgres postgres -c "SELECT pg_is_in_recovery();" -t 2>&1 | tr -d ' \n'
  echo
done

# 8. etcd health
docker exec pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health

# 9. pgBackRest stanza check
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 check
```

---

## Failover Testing

```bash
export PGPASSWORD='Pg@Lab2026!'

# Step 1: Identify current leader and sync standby (either pg1 or pg2 may be leader)
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
# Note the Leader and Sync Standby rows — use those names in the commands below.
# pg3 always has nosync:true and is never promoted.

# Step 2: Graceful switchover — swap leader and sync standby
# Replace <leader> with the current Leader node, <standby> with the Sync Standby node.
docker exec pg1 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader <leader> --candidate <standby> --force

# Step 3: Watch VIP migrate (run in a second terminal, re-runs every 2s)
watch -n 2 'for n in pg1 pg2 pg3; do echo -n "$n: "; docker exec $n ip addr show eth0 | grep "inet " | awk "{print \$2}"; done'

# Step 4: Verify write connection lands on new leader (HAProxy updates within ~9s)
sleep 10
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# Simulate node failure — stop the current leader (check with patronictl list first)
# The sync standby (pg1 or pg2) is automatically promoted — zero data loss
docker stop <leader>
sleep 15
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list   # former standby is now leader

# Recover failed node — it rejoins as replica and streams from the new leader
docker start <former-leader>
sleep 20
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list   # rejoined as replica
# Switchover back if desired (restore any preferred topology)
docker exec pg1 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader <current-leader> --candidate <former-leader> --force
```

---

## Disaster Recovery (DR) Testing: Complete Reference

### DR Quick Overview

Test **pg3 (async replica)** becoming the active leader when **pg1 (leader)** and **pg2 (sync standby)** fail.

**Key Points for Docker/macOS**:
- ⚠️ **Automatic failover is DISABLED** in this cluster configuration
- ⚠️ **pg3 is async (nosync: true)** — NOT eligible for automatic promotion
- ✓ **MANUAL command REQUIRED**: `docker exec pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force`
- ✓ After promotion, VIP (172.18.0.10) automatically migrates to pg3
- ✓ Writes safe on pg3 — data preserved when pg1/pg2 rejoin
- ✓ Zero application changes — apps reconnect to same VIP
- ✓ Replication catches up — LAG in MB → 0 after recovery

### DR Test Validation Matrix

Track cluster state at each phase of the test:

| Phase | Timeline | pg1 Role | pg2 Role | pg3 Role | pg1 State | pg2 State | pg3 State | VIP Location | Lag = 0 | Notes |
|-------|----------|----------|----------|----------|-----------|-----------|-----------|--------------|---------|-------|
| Pre-DR | 1 | Leader | Sync Standby | Replica | running | running | running | pg1 | ✓ | Initial state |
| After Stop | 1 | OFFLINE | OFFLINE | Replica | stopped | stopped | running | pg1 | — | pg3 still Replica (manual promotion needed) |
| After Promotion | 2 | OFFLINE | OFFLINE | Leader | stopped | stopped | running | pg3 | — | pg3 manually promoted, writes active |
| Recovery | 2 | catching up | catching up | Leader | running | running | running | pg3 | ✗ | Cluster reforming, replication lag high |
| Caught Up | 2 | Replica | Replica | Leader | running | running | running | pg3 | ✓ | Replication lag = 0, ready for switchover |
| After Switchover | 3 | Leader | Sync Standby | Replica | running | running | running | pg1 | ✓ | Original topology restored |

**Cycle 1**: Run full test (Pre-DR → Disaster → Promotion → DR Mode → Recovery → Switchover → Restore)  
**Cycle 2**: Repeat to verify consistency (target: timing delta < 5 seconds)

---

### Pre-DR Baseline Verification

#### Step 1: Verify Patroni cluster topology

```bash
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

**Expected output** (or run from pg2/pg3 if pg1 is not accessible):
```
+ Cluster: pg-docker-cls1 (7634451494908218688) --+-----------+
| Member | Host        | Role         | State     | TL | Lag in MB |
+--------+-------------+--------------+-----------+----+-----------+
| pg1    | 172.18.0.11 | Leader       | running   |  1 |           |
| pg2    | 172.18.0.12 | Sync Standby | streaming |  1 |       0.00|
| pg3    | 172.18.0.13 | Replica      | streaming |  1 |       0.00|
+--------+-------------+--------------+-----------+----+-----------+
```

**Verify**: pg1=Leader, pg2=Sync Standby, pg3=Replica, Timeline=1, Lag=0.00 MB

#### Step 2: Verify Keepalived VIP assignment

```bash
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  docker exec $n ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}'
done
```

**Expected output**:
```
pg1: 172.18.0.11/16 172.18.0.10/32  ← primary VIP on pg1 (leader)
pg2: 172.18.0.12/16 172.18.0.9/32   ← replica VIP on pg2 (sync standby)
pg3: 172.18.0.13/16                 ← no VIP on pg3 (async replica)
```

**Verify**: Primary VIP (172.18.0.10) on pg1 (leader), Replica VIP (172.18.0.9) on pg2 (sync standby)

#### Step 3: Verify HAProxy backend health

```bash
docker exec pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep "be_write\|be_read" | cut -d, -f1,2,18'
```

**Expected output**:
```
be_write,pg1,UP        ← pg1 is UP in write pool (leader)
be_read,pg2,UP         ← pg2 is UP in read pool (sync standby)
be_read,pg3,UP         ← pg3 is UP in read pool (replica)
```

**Verify**: pg1 UP in be_write, pg2 and pg3 UP in be_read

#### Step 4: Verify etcd cluster health

```bash
docker exec pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health
```

**Expected output**:
```
http://172.18.0.11:2379, healthy, got simple pong response
http://172.18.0.12:2379, healthy, got simple pong response
http://172.18.0.13:2379, healthy, got simple pong response
```

**Verify**: All 3 etcd nodes healthy

#### Step 5: Capture baseline replication state

```bash
docker exec pg1 bash -c "PGPASSWORD='Pg@Lab2026!' psql -h 172.18.0.11 -p 5432 -U postgres postgres -c \
  \"SELECT now() as baseline_time, 
          pg_current_wal_lsn() as lsn, 
          txid_current() as txid;\""
```

**Note**: Record these values for comparison after recovery

---

### Disaster Scenario

#### Step 1: Record current state before disaster

```bash
echo "=== PRE-DISASTER STATE ==="
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

#### Step 2: Stop pg1 (leader)

```bash
echo "Stopping pg1 (leader)..."
docker stop pg1
sleep 5
```

#### Step 3: Stop pg2 (sync standby)

```bash
echo "Stopping pg2 (sync standby)..."
docker stop pg2
sleep 5
```

#### Step 4: Verify pg1 & pg2 are DOWN, pg3 is still REPLICA

⚠️ **IMPORTANT**: When pg1 & pg2 are stopped, etcd loses quorum (2 of 3 nodes down). Patroni on pg3 cannot connect to the DCS. **Do NOT use `patronictl list`** — it will timeout.

Instead, directly query PostgreSQL on pg3 to verify it's still in recovery mode (replica):

```bash
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 127.0.0.1 -p 5432 -U postgres postgres -t -c "SELECT pg_is_in_recovery();"'
```

**Expected output**:
```
 t
(1 row)
```

**Verify**: pg3 returns `t` (true) — pg3 is still in recovery mode (replica status confirmed)

#### Step 5: Verify etcd accessibility from pg3

```bash
docker exec pg3 bash -c "etcdctl --endpoints=http://172.18.0.13:2379 endpoint health"
```

**Expected output**:
```
http://172.18.0.13:2379, healthy, got simple pong response
```

**Verify**: pg3 can communicate with etcd before promotion

#### Step 6: Verify pg3 can write to DCS

```bash
docker exec pg3 bash -c "patronictl -c /etc/patroni/patroni.yml show-config 2>&1 | head -5"
```

**Expected output**: Configuration output (no timeout errors)

**Verify**: DCS is responsive and accessible from pg3

---

### Manual Promotion

#### Step 1: Promote pg3 to Leader (MANUAL — required because auto-failover is disabled)

```bash
echo "Promoting pg3 to Leader (MANUAL - automatic failover disabled)..."
docker exec pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force
sleep 5
```

**Expected output**:
```
Failing over to a replica...
Failed over to 'pg3'
```

#### Step 2: Verify pg3 is now Leader

```bash
docker exec pg3 patronictl -c /etc/patroni/patroni.yml list
```

**Expected output**:
```
+ Cluster: pg-docker-cls1 (7634451494908218688) --+-----------+
| Member | Host        | Role    | State     | TL | Lag in MB |
+--------+-------------+---------+-----------+----+-----------+
| pg1    | 172.18.0.11 | Leader  | down      |  2 |       N/A |
| pg2    | 172.18.0.12 | Standby | down      |  2 |       N/A |
| pg3    | 172.18.0.13 | Leader  | running   |  2 |           |
+--------+-------------+---------+-----------+----+-----------+
```

**Verify**: pg3 is now Leader, Timeline advanced from 1 → 2

#### Step 3b: Verify pg3 Can Perform Writes

```bash
docker exec pg3 bash -c "PGPASSWORD='Pg@Lab2026!' psql -h 172.18.0.13 -p 5432 -U postgres postgres -c \
  \"SELECT is_wal_replay_paused(), pg_is_in_recovery();\""
```

**Expected output**:
```
 is_wal_replay_paused | pg_is_in_recovery
----------------------+-------------------
 f                    | f
(1 row)
```

**Verify**: WAL replay not paused, not in recovery (pg3 is ready for writes)

---

### DR Mode Active

#### Step 1: Verify VIP migrated to pg3

```bash
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  docker exec $n ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}' | tr '\n' ' ' || echo "offline"
  echo
done
```

**Expected output**:
```
pg1: offline
pg2: offline
pg3: 172.18.0.13/16 172.18.0.10/32     ← primary VIP migrated to pg3 (leader)
```

**Verify**: Primary VIP (172.18.0.10) on pg3 (new leader)

#### Step 2: Test pg3 accepts writes (DR mode active)

```bash
export PGPASSWORD='Pg@Lab2026!'

# Direct connection to pg3 leader
docker exec pg3 bash -c 'psql -h 172.18.0.13 -p 5432 -U postgres postgres -c \
  "CREATE TABLE IF NOT EXISTS dr_test AS SELECT now();
   INSERT INTO dr_test SELECT now();
   SELECT COUNT(*) FROM dr_test;"'
```

**Expected output**:
```
      now
-------------------
 2026-05-03 ...
(1 row)

INSERT 0 1
 count
-------
     2
(2 rows)
```

**Verify**: pg3 accepts writes, table creation and inserts succeed

#### Step 3: Verify HAProxy write pool health

```bash
docker exec pg3 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep "be_write" | cut -d, -f1,2,18'
```

**Expected output**:
```
be_write,pg3,UP     ← pg3 now in write pool (new leader)
```

**Verify**: HAProxy recognizes pg3 as write backend

#### Step 4: Verify pgBouncer connectivity via VIP

```bash
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
```

**Expected output**:
```
 inet_server_addr | pg_is_in_recovery
------------------+-------------------
 172.18.0.13      | f
(1 row)
```

**Verify**: VIP + HAProxy routes to pg3 (write endpoint accessible)

---

### Recovery Phase

#### Step 1: Restart pg1 and pg2

```bash
echo "Starting pg1 and pg2..."
docker start pg1 pg2
sleep 15
```

#### Step 2: Monitor cluster rejoin with timeline tracking (60+ seconds)

```bash
echo "Waiting for rejoin (monitor for 60 seconds)..."
for i in {1..12}; do
  echo "=== ${i}0 seconds ==="
  docker exec pg3 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep -E "Member|TL|Lag"
  sleep 5
done
```

**Expected progression**:
```
T=0:   pg1 Replica (catching up), pg2 Replica (catching up), pg3 Leader (TL=2, Lag=0)
T=5:   pg1 Replica (streaming), pg2 Replica (streaming) — replication lag high (50+ MB)
T=15:  Lag decreasing (30 MB → 20 MB → 10 MB)
T=30:  Lag approaching 0 (5 MB → 2 MB → 0 MB)
T=60:  Lag = 0.00 MB — both replicas caught up
```

**Verify**: Both pg1 and pg2 rejoin as replicas and eventually catch up to pg3 (Lag = 0)

#### Step 3: Monitor VIP migration during recovery

```bash
watch -n 2 'for n in pg1 pg2 pg3; do
  echo -n "$n: "
  docker exec $n ip addr show eth0 2>/dev/null | grep "inet " | awk "{print \$2}" | tr "\\n" " " || echo "offline"
  echo
done'
```

**Expected**: VIP stays on pg3 during rejoin (primary VIP follows the leader)

#### Step 4: Monitor replication lag progression (real-time)

```bash
echo "Monitoring lag (Ctrl+C to stop)..."
watch -n 3 'docker exec pg3 bash -c "
  PGPASSWORD=Pg@Lab2026! psql -h 172.18.0.13 -p 5432 -U postgres postgres -c \
  \"SELECT client_addr, state, 
          round((sent_lsn - replay_lsn) / 1048576.0, 2) AS lag_mb
   FROM pg_stat_replication ORDER BY client_addr;\"
"'
```

**Expected progression**:
```
First check:   lag_mb = 50.00, 48.00  (high lag, fast catchup)
After 15s:     lag_mb = 30.00, 28.00  (catchup continuing)
After 30s:     lag_mb = 10.00, 8.00   (nearing convergence)
After 45s:     lag_mb = 0.50, 0.25    (nearly caught up)
After 60s:     lag_mb = 0.00, 0.00    ✓ (fully caught up — target achieved)
```

**Verify**: Lag decreases over time until all replicas reach 0.00 MB

---

### Restore Topology

#### Step 1: Verify lag is zero before switchover

```bash
docker exec pg3 patronictl -c /etc/patroni/patroni.yml list
```

**Expected**: Lag in MB column = 0.00 for all nodes

#### Step 2: Switchover pg3 → pg1 (restore original topology)

```bash
echo "Switchover: pg3 (current leader) → pg1 (candidate)"
docker exec pg3 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader pg3 --candidate pg1 --force
sleep 10
```

**Expected output**:
```
Switchover initiated.
Switched over to 'pg1'
```

#### Step 3: Verify original topology restored

```bash
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

**Expected output**:
```
+ Cluster: pg-docker-cls1 (7634451494908218688) --+-----------+
| Member | Host        | Role         | State     | TL | Lag in MB |
+--------+-------------+--------------+-----------+----+-----------+
| pg1    | 172.18.0.11 | Leader       | running   |  3 |           |
| pg2    | 172.18.0.12 | Sync Standby | streaming |  3 |       0.00|
| pg3    | 172.18.0.13 | Replica      | streaming |  3 |       0.00|
+--------+-------------+--------------+-----------+----+-----------+
```

**Verify**: pg1=Leader, pg2=Sync Standby, pg3=Replica, Timeline=3, Lag=0.00 MB

#### Step 4: Verify VIP migrated back to pg1

```bash
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  docker exec $n ip addr show eth0 | grep "inet " | awk '{print $2}'
done
```

**Expected output**:
```
pg1: 172.18.0.11/16 172.18.0.10/32  ← primary VIP back on pg1
pg2: 172.18.0.12/16 172.18.0.9/32   ← replica VIP back on pg2
pg3: 172.18.0.13/16                 ← no VIP
```

**Verify**: VIPs restored to original nodes

---

### Post-Recovery Validation

#### Step 1: Verify all nodes operational

```bash
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

**Checklist**:
- [ ] pg1 = Leader (running)
- [ ] pg2 = Sync Standby (streaming)
- [ ] pg3 = Replica (streaming)
- [ ] Timeline = 3 (post-switchover)
- [ ] Lag in MB = 0.00 (all nodes caught up)

#### Step 2: Verify all services healthy

```bash
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n systemctl is-active patroni haproxy keepalived pgbouncer etcd
done
```

**Expected**: All services should return `active`

#### Step 3: Verify HAProxy backend health

```bash
docker exec pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep -v "^#\|FRONTEND" | cut -d, -f1,2,18'
```

**Expected**:
```
be_write,pg1,UP      ← pg1 in write pool
be_read,pg2,UP       ← pg2 in read pool
be_read,pg3,UP       ← pg3 in read pool
```

#### Step 4: Verify data preserved

```bash
export PGPASSWORD='Pg@Lab2026!'
docker exec pg1 bash -c 'psql -h 172.18.0.11 -p 5432 -U postgres postgres -c \
  "SELECT COUNT(*) FROM dr_test;"'
```

**Expected**:
```
 count
-------
     2
(1 row)
```

**Verify**: Data from dr_test table is still there (data preserved during DR)

#### Step 5: Verify write path works

```bash
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres postgres -c "INSERT INTO dr_test SELECT now(); SELECT COUNT(*) FROM dr_test;"'
```

**Expected output**:
```
INSERT 0 1
 count
-------
     3
(1 row)
```

**Verify**: Write path functional after recovery

#### Step 6: Verify read path works

```bash
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5001 \
  -U postgres postgres -c "SELECT inet_server_addr(), COUNT(*) FROM dr_test;"'
```

**Expected output**:
```
 inet_server_addr | count
------------------+-------
 172.18.0.1[2-3]  |     3
(1 row)
```

**Verify**: Read path routes to a replica (not pg1)

---

### Understanding Timeline & LSN

#### What is Timeline?

PostgreSQL's timeline tracks branching in WAL history. Each failover creates a new timeline:

- **Timeline 1**: Normal operation (pg1 leader, pg2 sync standby, pg3 replica)
- **Timeline 2**: After pg3 promotion (pg3 becomes leader, pg1/pg2 become replicas)
- **Timeline 3**: After switchover back to pg1 (pg1 becomes leader again)

Timeline progression is **not reset** — it strictly increases on each failover/switchover/promotion.

#### Check timeline on each node:

```bash
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  docker exec $n bash -c "PGPASSWORD='Pg@Lab2026!' psql -h 127.0.0.1 -p 5432 -U postgres postgres -t -c \
    \"SELECT timeline_id FROM pg_control_checkpoint();\""
done
```

**Expected progression**:
```
At Pre-DR:        pg1: 1, pg2: 1, pg3: 1
At Post-Promotion: pg1: 1 (down), pg2: 1 (down), pg3: 2  ← pg3 advanced to TL=2
At Post-Recovery:  pg1: 2, pg2: 2, pg3: 2                ← pg1/pg2 rejoin at TL=2
At Post-Switchover: pg1: 3, pg2: 3, pg3: 3               ← all advance to TL=3
```

**Why it matters**: Timeline advancement shows that the cluster successfully transitioned through the failover/promotion/recovery cycle. Stuck timeline indicates a problem (e.g., wal_level too low, WAL archiving blocking).

#### What is LSN?

LSN (Log Sequence Number) is PostgreSQL's internal pointer to a position in the WAL stream.

- **sent_lsn**: WAL position sent from primary to replica
- **replay_lsn**: WAL position replayed (applied) on the replica
- **Lag = sent_lsn - replay_lsn** (measured in MB)

#### Check LSN on all nodes (run on leader):

```bash
export PGPASSWORD='Pg@Lab2026!'
docker exec pg1 bash -c 'psql -h 172.18.0.11 -p 5432 -U postgres postgres -c \
  "SELECT client_addr, 
          pg_wal_lsn_diff(sent_lsn, replay_lsn) / 1048576.0 as lag_mb,
          replay_lsn
   FROM pg_stat_replication ORDER BY client_addr;"'
```

**Expected output at different phases**:
```
After disaster: 
  - pg1 offline
  - pg2 offline
  - pg3 (new leader) lag unknown (is primary, not replica)

During recovery:
  - pg1: lag_mb = 50.00, replay_lsn = 0/XXXXXXXX
  - pg2: lag_mb = 48.00, replay_lsn = 0/XXXXXXXX
  
After catchup:
  - pg1: lag_mb = 0.00, replay_lsn = 0/YYYYYYYY (caught up)
  - pg2: lag_mb = 0.00, replay_lsn = 0/YYYYYYYY (caught up)
```

---

### Replication Slots During DR

PostgreSQL replication slots track which WAL has been consumed by each replica.

#### Check slot status before DR:

```bash
export PGPASSWORD='Pg@Lab2026!'
docker exec pg1 bash -c 'psql -h 172.18.0.11 -p 5432 -U postgres postgres -c \
  "SELECT slot_name, slot_type, active, restart_lsn FROM pg_replication_slots;"'
```

**Expected output (pre-DR)**:
```
 slot_name | slot_type | active | restart_lsn
-----------+-----------+--------+-------------
 pg2       | physical  | t      | 0/XXXXXXXX
 pg3       | physical  | t      | 0/XXXXXXXX
(2 rows)
```

#### After pg1/pg2 are stopped:

Slots remain but show `active = f` (no active consumer):

```bash
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.13 -p 5432 -U postgres postgres -c \
  "SELECT slot_name, slot_type, active, restart_lsn FROM pg_replication_slots;"'
```

**Expected**:
```
 slot_name | slot_type | active | restart_lsn
-----------+-----------+--------+-------------
 pg1       | physical  | f      | 0/XXXXXXXX  ← pg1 slot inactive (pg1 offline)
 pg2       | physical  | f      | 0/XXXXXXXX  ← pg2 slot inactive (pg2 offline)
(2 rows)
```

#### After pg1/pg2 rejoin:

Slots re-activate immediately:

```bash
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.13 -p 5432 -U postgres postgres -c \
  "SELECT slot_name, slot_type, active, restart_lsn FROM pg_replication_slots;"'
```

**Expected**:
```
 slot_name | slot_type | active | restart_lsn
-----------+-----------+--------+-------------
 pg1       | physical  | t      | 0/YYYYYYYY  ← pg1 slot active, LSN updated
 pg2       | physical  | t      | 0/YYYYYYYY  ← pg2 slot active, LSN updated
(2 rows)
```

**Why it matters**: Slots prevent WAL pruning while replicas are down, allowing them to rejoin without full resync. If a replica stays down too long, the primary's wal_keep_size may fill up.

---

### DR Troubleshooting

#### Promotion fails with "Already a Leader"

**Symptom**: `patronictl failover` returns error: `Already a leader`

**Cause**: pg3 may already be the leader (benign), or promoter command didn't parse correctly.

**Fix**:
```bash
# Verify current state
docker exec pg3 patronictl -c /etc/patroni/patroni.yml list

# If pg3 is already Leader, continue with writes test
# If pg3 is still Replica, retry:
docker exec pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force
sleep 5
docker exec pg3 patronictl -c /etc/patroni/patroni.yml list
```

#### Timeline not advancing during promotion

**Symptom**: Timeline stuck at 1 even after pg3 promotion.

**Cause**: WAL archiving failing, or PostgreSQL control file corruption.

**Diagnostic steps**:
```bash
# Check PostgreSQL log for errors
docker exec pg3 grep -i "timeline\|archive\|ERROR" /var/log/postgresql/postgresql-$(date +%a).log | tail -20

# Check if pg3 has write access to WAL archive
docker exec pg3 ls -la /var/lib/pgbackrest/

# Try forcing a write on pg3
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 127.0.0.1 -p 5432 -U postgres postgres \
  -c "CREATE TABLE timeline_test AS SELECT 1; DROP TABLE timeline_test;"'

# Verify timeline after write
docker exec pg3 bash -c "PGPASSWORD='Pg@Lab2026!' psql -h 127.0.0.1 -p 5432 -U postgres postgres -t -c \
  \"SELECT timeline_id FROM pg_control_checkpoint();\""
```

#### Switchover hangs or takes long

**Symptom**: `patronictl switchover` command hangs for >30 seconds or fails.

**Cause**: Long-running transaction on current leader blocking replication.

**Fix**:
```bash
# Identify long-running queries on current leader (pg3 in this case)
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 127.0.0.1 -p 5432 -U postgres postgres -c \
  "SELECT pid, now()-query_start AS duration, state, query 
   FROM pg_stat_activity 
   WHERE query_start < now() - interval '\''5 seconds'\'' 
   ORDER BY duration DESC;"'

# Kill blocking query if found (get pid from above)
# WARNING: Only do this if you own the query!
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 127.0.0.1 -p 5432 -U postgres postgres -c \
  "SELECT pg_terminate_backend(<pid>);"'

# Retry switchover
docker exec pg3 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader pg3 --candidate pg1 --force
```

#### HAProxy not updated after failover

**Symptom**: HAProxy still routes writes to pg1 even though pg3 is leader.

**Cause**: HAProxy health checks not updated (6–9 second lag typical).

**Fix**:
```bash
# Monitor HAProxy backend status
watch -n 2 'docker exec pg3 bash -c "
  curl -s -u \"admin:Pg@Lab2026!\" \"http://127.0.0.1:7000/;csv\" \
  | grep \"be_write\|be_read\" | cut -d, -f1,2,18
"'

# Wait 10–15 seconds for automatic refresh
# If still not updated, manually reload HAProxy
for n in pg1 pg2 pg3; do docker exec $n systemctl reload haproxy; done
```

---

### Complete DR Test Verification Checklist

Use this checklist for each DR test cycle (Cycle 1 and Cycle 2).

#### Before Starting (Pre-Test)
- [ ] All 3 containers running: `docker ps | grep pg`
- [ ] Patroni topology correct: `docker exec pg1 patronictl -c /etc/patroni/patroni.yml list`
- [ ] VIP assignments correct: pg1=172.18.0.10, pg2=172.18.0.9, pg3=none
- [ ] All services healthy: `for n in pg1 pg2 pg3; do docker exec $n systemctl is-active patroni; done`
- [ ] Replication lag = 0.00 MB
- [ ] etcd healthy: `docker exec pg1 etcdctl endpoint health`
- [ ] HAProxy backends UP: `curl -s -u admin:Pg@Lab2026! http://localhost:7000/;csv | grep be_`
- [ ] pgBackRest stanza valid: `docker exec pg1 pgbackrest --stanza=pg-docker-cls1 check`
- [ ] Baseline data captured: record output from Step 5 in Pre-DR Baseline Verification

#### Cycle 1: Full DR Test (All 4 Phases)

**Phase 1: Disaster & Promotion (T=0 to T=20s)**
- [ ] Stopped pg1
- [ ] Stopped pg2
- [ ] pg3 promoted via `patronictl failover --force`
- [ ] pg3 now shows Role=Leader
- [ ] Timeline advanced 1→2
- [ ] VIP migrated 172.18.0.10 to pg3
- [ ] pg3 accepts writes (dr_test table created)
- [ ] HAProxy be_write shows pg3 UP

**Phase 2: DR Mode Active (T=20 to T=30s)**
- [ ] pg3 is writable leader
- [ ] VIP 172.18.0.10 on pg3
- [ ] Replica VIP 172.18.0.9 unassigned (no sync standby)
- [ ] Data inserted into dr_test table successfully
- [ ] pgBouncer routing via VIP works

**Phase 3: Recovery & Rejoin (T=30 to T=90s)**
- [ ] Started pg1
- [ ] Started pg2
- [ ] pg1 rejoins as Replica
- [ ] pg2 rejoins as Replica (or Sync Standby after catchup)
- [ ] Replication lag >0 initially
- [ ] Lag progressively decreases
- [ ] Lag reaches 0.00 MB within ~60s
- [ ] Timeline still at 2 (no new promotion)
- [ ] All nodes streaming

**Phase 4: Switchover & Restore (T=90 to T=110s)**
- [ ] Executed switchover pg3→pg1
- [ ] pg1 now shows Role=Leader
- [ ] pg2 now shows Role=Sync Standby
- [ ] pg3 now shows Role=Replica
- [ ] Timeline advanced 2→3
- [ ] VIP migrated 172.18.0.10 back to pg1
- [ ] Replica VIP 172.18.0.9 on pg2
- [ ] All nodes streaming
- [ ] Lag = 0.00 MB
- [ ] Data in dr_test table preserved (count=2 or more)

**Post-Phase 4 Validation**
- [ ] All services running: `systemctl is-active patroni haproxy keepalived pgbouncer etcd`
- [ ] Writes work: `INSERT INTO dr_test SELECT now();`
- [ ] Reads work: `SELECT COUNT(*) FROM dr_test;`
- [ ] All error logs checked: `grep -i ERROR /var/log/postgresql/postgresql-*.log`

#### Cycle 2: Consistency Verification (Repeat Cycle 1, then compare)

**Run Cycle 1 again immediately (same steps as above)**
- [ ] Complete all 4 phases again
- [ ] Record timing for each milestone

**Comparison: Δ < 5 seconds**
- [ ] T(promotion) Cycle 1 vs Cycle 2: Δ < 5 seconds  
- [ ] T(lag catchup) Cycle 1 vs Cycle 2: Δ < 5 seconds  
- [ ] T(switchover) Cycle 1 vs Cycle 2: Δ < 5 seconds  
- [ ] T(total cycle) Cycle 1 vs Cycle 2: Δ < 5 seconds  

**Consistency Checks**
- [ ] Role transitions in same order (both cycles)
- [ ] Timeline progression identical (both cycles)
- [ ] LAG pattern matches (high→decreasing→zero)
- [ ] VIP migration timing similar
- [ ] Data integrity maintained
- [ ] No error messages in logs (both cycles)

---

### DR Test Execution Guide

**Timeline**: Cycle 1 takes ~90–120 seconds; Cycle 2 takes ~90–120 seconds (goal: Δ < 5 sec)

#### Preparation (5 min)

```bash
# Terminal 1: Reserve for monitoring
# Terminal 2: Reserve for commands

# In Terminal 1 — open live monitoring dashboard
watch -n 2 'echo "=== PATRONI STATE ===" && \
  docker exec pg3 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep -E "Member|TL|Lag" && \
  echo "" && \
  echo "=== VIP ASSIGNMENT ===" && \
  for n in pg1 pg2 pg3; do echo -n "$n: "; docker exec $n ip addr show eth0 2>/dev/null | grep "inet " | awk "{print \$2}" | tr "\n" " " || echo "offline"; echo; done'

# In Terminal 2 — run pre-test checklist
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

#### Cycle 1 Execution (90–120 seconds)

**T=0: Start disaster**
```bash
# Terminal 2
echo "[T=0] Stopping pg1..."
docker stop pg1
sleep 2
echo "[T=2] Stopping pg2..."
docker stop pg2
sleep 3

echo "[T=5] Verifying pg1/pg2 stopped, pg3 still Replica..."
docker exec pg3 patronictl -c /etc/patroni/patroni.yml list
```

**T=8: Promote pg3**
```bash
echo "[T=8] Promoting pg3 to Leader..."
docker exec pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force
sleep 5

echo "[T=13] Verifying pg3 is Leader (Timeline should be 2)..."
docker exec pg3 patronictl -c /etc/patroni/patroni.yml list
```

**T=15: Test DR mode**
```bash
echo "[T=15] Testing pg3 accepts writes..."
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.13 -p 5432 -U postgres postgres -c \
  "CREATE TABLE IF NOT EXISTS dr_test AS SELECT now();
   INSERT INTO dr_test SELECT now();
   SELECT COUNT(*) FROM dr_test;"'

echo "[T=20] Recording write count before recovery..."
WRITE_COUNT_BEFORE=$(docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.13 -p 5432 -U postgres postgres -t -c "SELECT COUNT(*) FROM dr_test;"')
echo "Write count: $WRITE_COUNT_BEFORE"
```

**T=25: Start recovery**
```bash
echo "[T=25] Starting pg1 and pg2..."
docker start pg1 pg2
sleep 10

echo "[T=35] Monitoring lag (Ctrl+C after 60s)..."
for i in {1..12}; do
  echo "[T=$((25+5*i))] $(docker exec pg3 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep Lag | head -3)"
  sleep 5
done
```

**T=90: Verify recovery complete**
```bash
echo "[T=90] Verifying lag = 0 for all nodes..."
docker exec pg3 patronictl -c /etc/patroni/patroni.yml list | grep "Lag"
```

**T=95: Switchover**
```bash
echo "[T=95] Switchover pg3 → pg1..."
docker exec pg3 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader pg3 --candidate pg1 --force
sleep 10

echo "[T=105] Verifying topology restored..."
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

**T=110: Cycle 1 complete**
```bash
echo "[T=110] CYCLE 1 COMPLETE"
echo "Summary:"
echo "  Timeline progression: 1 → 2 → 3"
echo "  VIP migration: pg1 → pg3 → pg1"
echo "  Data preserved: $(docker exec pg1 bash -c 'PGPASSWORD=Pg@Lab2026! psql -h 172.18.0.11 -p 5432 -U postgres postgres -t -c "SELECT COUNT(*) FROM dr_test;"')"

# Record these times for comparison with Cycle 2
echo "Record times above for consistency check with Cycle 2"
```

#### Cycle 2 Execution (Repeat steps, record timings)

```bash
echo "[CYCLE 2] Starting second iteration for consistency check..."
# Repeat all steps from T=0 to T=110 with same commands
# Monitor for timing consistency: goal Δ < 5 seconds
```

#### Final Validation

```bash
echo "[FINAL] Post-test checklist"
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
for n in pg1 pg2 pg3; do docker exec $n systemctl is-active patroni haproxy keepalived pgbouncer etcd; done
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 check
echo "All checks passed!"
```

---

## Troubleshooting

### pgBouncer SASL authentication failed

Symptom: `FATAL: SASL authentication failed` when connecting through pgBouncer.

Cause: Stale server-side pool connections (common after a Patroni failover/restart).

```bash
# Fix: reload pgBouncer to clear stale connections
for n in pg1 pg2 pg3; do docker exec $n systemctl reload pgbouncer; done
```

### Keepalived VIP not assigned (silent failure)

Symptom: `ip addr show eth0` shows no VIP despite Keepalived running.

Common cause: Interface label too long (Linux limit: 15 chars). Check the log:

```bash
docker exec pg1 journalctl -u keepalived --no-pager | grep -i "label\|removing\|no VIP"
```

Fix: Ensure labels in `keepalived.conf.j2` are ≤15 chars (e.g., `eth0:vip`, `eth0:rvip`).

### HAProxy backend shows all DOWN

Symptom: All backends DOWN in `be_write` or `be_read`.

```bash
# Check if Patroni REST API is reachable
for n in pg1 pg2 pg3; do
  echo -n "$n /primary: "
  docker exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary
  echo
done

# Restart HAProxy if needed
for n in pg1 pg2 pg3; do docker exec $n systemctl restart haproxy; done
```

### Patroni failover not happening

```bash
# Check if Patroni is paused
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list | grep -i pause

# Resume if paused
docker exec pg2 patronictl -c /etc/patroni/patroni.yml resume

# Check etcd connectivity (DCS required for failover)
docker exec pg2 etcdctl --endpoints=http://172.18.0.12:2379 endpoint health
```

### Replica lagging behind

```bash
# Check lag
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list

# Reinitialize lagging replica from scratch
docker exec pg2 patronictl -c /etc/patroni/patroni.yml reinit pg-docker-cls1 pg3 --force
```

### pgBackRest stanza system-id mismatch

**Symptom**: Backup fails with error:
```
ERROR: [051]: PostgreSQL version X, system-id XXXXXXXXX do not match stanza version X, system-id YYYYYYYYY
HINT: is this the correct stanza?
```

**Cause**: The pgBackRest stanza was created with a different PostgreSQL instance (different system-id).
This happens when the PostgreSQL cluster is reinitialized (via `reinit_cluster=true` in Ansible or
manual data directory reset) but the old pgBackRest stanza metadata still exists in `/var/lib/pgbackrest`.

**Fix**: Delete the old stanza and create a new one (this will remove all old backups for this stanza):

```bash
# SSH into the leader container and switch to postgres user
docker exec -it pg1 bash
su - postgres

# Delete the old stanza (all backups for this stanza will be removed)
pgbackrest --stanza=pg-docker-cls1 stanza-delete --force

# Create a new stanza synchronized with the current PostgreSQL instance
pgbackrest --stanza=pg-docker-cls1 stanza-create

# Verify the stanza is now valid
pgbackrest --stanza=pg-docker-cls1 check

# Exit back to root
exit
exit

# Now run a full backup
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info backup --type=full
```

**Note**: The stanza-delete + stanza-create cycle re-synchronizes pgBackRest with the current
PostgreSQL instance (system-id, wal_system_identifier, and other metadata).

### Primary VIP (172.18.0.10) unreachable after switchover/failover

**This should no longer happen automatically** — VIP assignment is handled by the Keepalived
notify scripts (`keepalived_notify_primary.sh` / `keepalived_notify_replica.sh`), which force
`ip addr add/del` + `arping` on every VRRP state transition regardless of Keepalived's internal
state. The `patroni_pgbouncer_callback.sh` callback only updates pgBouncer's target host; it does
**not** restart Keepalived.

If it still occurs (e.g. after a manual Keepalived restart or container recreation):

Symptom: `No route to host` connecting to 172.18.0.10, even though `patronictl list` shows the
correct leader and Keepalived is active.

Cause: Race condition — Keepalived entered MASTER state internally but failed to add the VIP to
the interface.

```bash
# Identify which node is the current Patroni primary
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list

# Check current VIP assignments
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  docker exec $n ip addr show eth0 | grep "inet " | awk '{print $2}' | tr '\n' ' '; echo
done

# Restart Keepalived on the primary node to re-acquire the VIP
docker exec <primary_node> systemctl restart keepalived
sleep 5

# Verify VIP is now assigned
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  docker exec $n ip addr show eth0 | grep "inet " | awk '{print $2}' | tr '\n' ' '; echo
done
```

### HAProxy host ports connection refused from Mac (e.g. localhost:25000)

Symptom: `psql: error: connection to server at "localhost", port 25000 failed: Connection refused`

Cause: Containers were created before the HAProxy host-port mappings were added to the Ansible
`pg_containers` definition. Docker port mappings are baked in at container creation time and cannot
be changed without recreating the container.

```bash
# Verify whether the ports are actually mapped on the running containers
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep pg

# If ports like 15000/25000/35000 are missing, recreate containers:
# 1. Destroy containers (volumes are named and survive this step — data is safe)
docker rm -f pg1 pg2 pg3

# 2. Recreate with correct port mappings (reads from roles/docker_infrastructure/defaults/main.yml)
ansible-playbook playbook-setup-docker.yml

# 3. Reinstall cluster software on the fresh containers
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml --vault-password-file=vault-pass
```

### psql password authentication failed despite correct ~/.pgpass

Symptom: `FATAL: password authentication failed` even though `~/.pgpass` has the right entry.

Cause: The `PGPASSWORD` environment variable takes precedence over `~/.pgpass`. If it is set to an
old or wrong value in the current shell session (e.g. from `~/.vars_personal`), it will override
the password file silently.

```bash
# Check what PGPASSWORD is set to in the current shell
echo "PGPASSWORD=${PGPASSWORD}"

# Fix: reload the env file (if ~/.vars_personal has been corrected)
source ~/.vars_personal

# Or unset PGPASSWORD entirely to fall back to ~/.pgpass
unset PGPASSWORD

# Verify ~/.vars_personal has the correct password
grep PGPWD ~/.vars_personal   # should show Pg@Lab2026!

# Verify ~/.pgpass has correct entries and permissions
cat ~/.pgpass
ls -la ~/.pgpass   # must be 600
```

### Writes hanging / primary blocked waiting for sync standby

Symptom: write queries hang indefinitely; `pg_stat_replication` shows `sync_state = sync` for the
sync standby but `sent_lsn != flush_lsn`.

Cause: The sync standby (whichever of pg1/pg2 holds that role) is down or lagging. The primary
waits for it to confirm WAL receipt before committing (`synchronous_commit = on`,
`synchronous_node_count = 1`).

```bash
# Check replication state on primary — use pg-primary or patronictl list to identify it first
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
pg-primary -c "SELECT client_addr, state, sync_state, sent_lsn, flush_lsn FROM pg_stat_replication;"

# Check Patroni status on the sync standby node
docker exec <sync-standby-node> systemctl status patroni

# If the sync standby is down and you need writes to continue immediately — temporarily switch to async:
docker exec pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 \
  --force -p synchronous_mode=false
# Restore sync mode once the sync standby is back and caught up:
docker exec pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 \
  --force -p synchronous_mode=true
```

### Container won't start after Docker Desktop restart

```bash
docker start pg1 pg2 pg3
sleep 5
# Services (patroni, etcd, pgbouncer, haproxy, keepalived) are enabled and auto-start
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

### etcd quorum lost (2 of 3 nodes down)

The cluster becomes read-only (no Patroni operations). Restart at least 2 nodes:

```bash
docker start pg1 pg2
sleep 10
docker exec pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379 \
  endpoint health
```

---

---

## Common Ansible Operations

```bash
cd playbook-install-pg-cluster-docker/

# Full cluster install (Phase 1 + Phase 2)
ansible-playbook playbook-setup-docker.yml
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml --vault-password-file=vault-pass

# Install/reconfigure a single component only
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags haproxy
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags keepalived
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags haproxy,keepalived
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags patroni
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags pgbouncer
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags pgbackrest
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags etcd

# Reinitialize cluster (DESTROYS ALL DATA — keeps packages)
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true

# Reinitialize without confirmation prompt (CI/automation)
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true -e skip_confirm=true

# Reinitialize + wipe all pgBackRest backups
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass \
  -e reinit_cluster=true -e skip_confirm=true -e cleanup_pgbackrest_backups=true

# Edit vault credentials
ansible-vault edit sensitive-values --vault-password-file=vault-pass

# SSH into containers
ssh -i ~/.ssh/id_ed25519 -p 2221 -o StrictHostKeyChecking=no ansible@127.0.0.1   # pg1
ssh -i ~/.ssh/id_ed25519 -p 2222 -o StrictHostKeyChecking=no ansible@127.0.0.1   # pg2
ssh -i ~/.ssh/id_ed25519 -p 2223 -o StrictHostKeyChecking=no ansible@127.0.0.1   # pg3

# Stop/start all pg containers
docker stop pg1 pg2 pg3 && docker start pg1 pg2 pg3

# Full teardown — WARNING: destroys all data
docker rm -f pg1 pg2 pg3
docker volume rm pg-data-pg1 pg-data-pg2 pg-data-pg3 \
                 pg-logs-pg1 pg-logs-pg2 pg-logs-pg3 pg-backups
```

---

## Prometheus Scrape Config

```yaml
scrape_configs:
  - job_name: postgresql_docker
    static_configs:
      - targets:
          - 'host.docker.internal:9194'   # pg1
          - 'host.docker.internal:9195'   # pg2
          - 'host.docker.internal:9196'   # pg3
        labels:
          cluster: pg-docker-cls1
          env: docker-local

# Reload Prometheus after editing
# curl -X POST http://localhost:9090/-/reload
```

---

## Design Notes

- **No shared proxy container**: HAProxy + Keepalived run on every pg container. The VIP floats
  to the right node — no SPOF proxy tier. All 3 nodes can handle the write path if the VIP moves.

- **Keepalived unicast mode**: Docker bridge networks don't reliably support multicast (needed by
  default VRRP). We configure `unicast_src_ip` / `unicast_peer` to route VRRP advertisements
  directly between container IPs.

- **VIP weight logic**: `vrrp_script` adds +100 to the base priority (101/100/99) when the health
  check passes. Primary node effective priority: 201/200/199. Replicas: 101/100/99. Guarantees the
  primary always holds the primary VIP, and no node holds both VIPs simultaneously.

- **Keepalived notify scripts** (`keepalived_notify_primary.sh` / `keepalived_notify_replica.sh`):
  deployed to `/usr/local/bin/` on each node. Called by Keepalived on every VRRP state transition
  (MASTER/BACKUP/FAULT). On MASTER: force `ip addr add <VIP>` + `arping` to gratuitously announce
  the VIP on the network. On BACKUP/FAULT: force `ip addr del <VIP>`. This bypasses Keepalived's
  internal VIP management which silently fails inside Docker containers.

- **pgBouncer `auth_type = scram-sha-256`**: Plain text passwords in `userlist.txt` are supported
  by pgBouncer 1.16+ for SCRAM authentication. After Patroni failovers, reload pgBouncer to clear
  stale server-side connections (`systemctl reload pgbouncer`).

- **Patroni `on_role_change` callback** (`patroni_pgbouncer_callback.sh`): fires on every leader
  transition (switchover, failover, promotion). Updates pgBouncer's `host=` to the new leader IP
  and reloads pgBouncer. It does **not** restart Keepalived — VIP management is handled exclusively
  by `keepalived_notify_primary.sh` and `keepalived_notify_replica.sh`, which force `ip addr add/del`
  and `arping` on every VRRP state transition. This eliminates the race condition where Keepalived
  enters MASTER state internally but fails to add the VIP to the interface.

- **HAProxy host ports**: The HAProxy host-port mappings (15000/25001/17000 etc.) were added to
  container definitions in `roles/docker_infrastructure/defaults/main.yml` but only take effect
  when containers are recreated. The container-internal ports (5000/5001/7000) are always active.

- **Synchronous replication**: `synchronous_mode: true` with `synchronous_node_count: 1` — every
  commit on the leader must be acknowledged by the sync standby (whichever of pg1/pg2 holds that
  role) before returning to the client. pg3 is excluded via `nosync: true` and never holds the sync
  standby role. If the sync standby goes down, writes on the leader will block until it recovers (or
  sync mode is temporarily disabled via `patronictl edit-config`). Failover between pg1 and pg2 is
  always zero data loss.

- **Passwords**: must NOT contain `$` (PostgreSQL dollar-quote delimiter breaks Patroni post-bootstrap SQL).

- **pgBackRest stanza**: created once on the leader. All nodes share the same POSIX repo via the
  `pg-backups` Docker named volume mounted at `/var/lib/pgbackrest`.

---

## Other Miscellaneous Commands

### Unset Env Variable
```
unset PGPASSWORD
```

### Connect to docker container prompt, and connect to postgresql
```
ajaydwivedi@Ajays-MacBook-Pro PostgreSQL-Learning % docker exec -it pg2 bash
root@pg2:/# patronictl -c /etc/patroni/patroni.yml list
+ Cluster: pg-docker-cls1 (7634451494908218688) --+-----------+
| Member | Host        | Role    | State     | TL | Lag in MB |
+--------+-------------+---------+-----------+----+-----------+
| pg1    | 172.18.0.11 | Replica | streaming |  2 |         0 |
| pg2    | 172.18.0.12 | Leader  | running   |  2 |           |
| pg3    | 172.18.0.13 | Replica | streaming |  2 |         0 |
+--------+-------------+---------+-----------+----+-----------+
root@pg2:/# 
root@pg2:/# su - postgres
postgres@pg2:~$ psql
psql (18.3 (Ubuntu 18.3-1.pgdg24.04+1))
Type "help" for help.

postgres=# 
postgres=# \q
postgres@pg2:~$ exit
logout
root@pg2:/# 

```

### Add environment variable
```
tee -a ~/.bashrc << 'EOF'

export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
EOF
```


### Add host entries inside docker
```
tee -a /etc/hosts << 'EOF'

# PostgreSQL Docker cluster — lab-network 172.18.0.0/16
172.18.0.11  pg1    # PostgreSQL :5433  pgBouncer :6433  Patroni :8011
172.18.0.12  pg2    # PostgreSQL :5434  pgBouncer :6434  Patroni :8012
172.18.0.13  pg3    # PostgreSQL :5435  pgBouncer :6435  Patroni :8013

172.18.0.10 pg-primary pg-leader
172.18.0.9  pg-replica
EOF
```

### Take SSH of pg1 container
```
ssh -p 2221 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/id_ed25519 ansible@127.0.0.1 "patronictl -c /etc/patroni/patroni.yml list" 2>/dev/null
```
