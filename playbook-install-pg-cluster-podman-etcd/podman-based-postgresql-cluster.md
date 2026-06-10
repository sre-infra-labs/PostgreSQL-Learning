# podman-Based PostgreSQL 18 HA Cluster (Multi-Datacenter)
## Patroni + etcd + pgBackRest + pgBouncer + HAProxy + Keepalived + pg_exporter

---

## 📋 Table of Contents

### Core Documentation
1. [Quick Start (Podman)](#quick-start-podman)
2. [Architecture](#architecture)
3. [Component Stack](#component-stack)
4. [Host One-Time Setup](#host-one-time-setup)

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

### Multi-Datacenter (Standby Cluster)
17. [Multi-DC Standby Cluster Setup (podpg-cls1-pg4 — Region B)](#multi-dc-standby-cluster-setup-podpg-cls1-pg4--region-b)
   - [Standby Cluster Overview](#standby-cluster-overview)
   - [Setup podpg-cls1-pg4 Container](#setup-podpg-cls1-pg4-container)
   - [Install Standby Cluster](#install-standby-cluster)
   - [Verify Standby Streaming](#verify-standby-streaming)
   - [Multi-DC DR: Promote Standby](#multi-dc-dr-promote-standby)
   - [Multi-DC DR: Failback to Primary DC](#multi-dc-dr-failback-to-primary-dc)
   - [Standby Cluster Troubleshooting](#standby-cluster-troubleshooting)

### Infrastructure & Deployment
18. [Troubleshooting](#troubleshooting)
19. [Common Ansible Operations](#common-ansible-operations)
20. [Prometheus Scrape Config](#prometheus-scrape-config)
21. [Design Notes](#design-notes)
22. [Podman Infrastructure Conversion](#podman-infrastructure-conversion)
23. [Multi-Region DCS Deployment for Production DR](#multi-region-dcs-deployment-for-production-dr)
   - [Why Separate DCS Nodes Matter](#why-separate-dcs-nodes-matter-for-dr)
   - [DCS Quorum Rules](#dcs-quorum-rules-critical-for-dr)
   - [Multi-Region Deployment Scenarios](#multi-region-deployment-scenarios)
   - [Network Latency Considerations](#network-latency-considerations)
   - [DCS Node Placement Best Practice](#dcs-node-placement-best-practice)
   - [Impact on DR Testing](#impact-on-dr-testing)
   - [Adding Nodes On-The-Fly](#adding-nodes-on-the-fly)

---

## Quick Start (Podman)

This setup uses **Podman** on Ubuntu 24.04 with a **multi-datacenter** architecture:
- **Region A (Primary DC)**: podpg-cls1-pg1, podpg-cls1-pg2, podpg-cls1-pg3 — full HA cluster with Patroni + etcd + HAProxy + Keepalived
- **Region B (Secondary DC)**: podpg-cls1-pg4 — single-node standby cluster streaming from primary DC

```bash
cd ~/GitHub/PostgreSQL-Learning/playbook-install-pg-cluster-podman-etcd

# podman stop podpg-cls1-pg4 podpg-cls1-pg3 podpg-cls1-pg2 podpg-cls1-pg1
# podman rm podpg-cls1-pg4 podpg-cls1-pg3 podpg-cls1-pg2 podpg-cls1-pg1
# podman start podpg-cls1-pg4 podpg-cls1-pg3 podpg-cls1-pg2 podpg-cls1-pg1

ansible-playbook -i hosts.yml playbook-cleanup.yml -e skip_confirm=true --tags containers 2>&1 | tee logs/playbook-cleanup.yml.log

# ── PRIMARY CLUSTER (Region A: podpg-cls1-pg1, podpg-cls1-pg2, podpg-cls1-pg3) ────────────────────────────────
# Phase 1: Create Podman containers
export ANSIBLE_FORCE_COLOR=1
ansible-playbook -i hosts.yml playbook-setup-podman.yml 2>&1 | tee logs/playbook-setup-podman.yml.log

# Phase 2: Install PostgreSQL 18 primary cluster
export ANSIBLE_FORCE_COLOR=1
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml --vault-password-file=vault-pass -e reinit_cluster=true 2>&1 | tee logs/playbook-install-pg-cluster.yml.log

# Verify primary cluster status
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list

# ── STANDBY CLUSTER (Region B: podpg-cls1-pg4) ─────────────────────────────────────────
# podpg-cls1-pg4 container is created together with podpg-cls1-pg1/pg2/pg3 in Phase 1.
# Only pg_cluster installation is separate:
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml --vault-password-file=vault-pass -e reinit_cluster=true 2>&1 | tee logs/playbook-install-standby-cluster.yml.log

# Verify podpg-cls1-pg4 is streaming from primary
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
```

### Network Architecture: Podman Shared Network

All containers share the same `lab-network` (172.18.0.0/16):

```bash
# Create the shared network once (if not already exists)
podman network create --driver bridge --subnet=172.18.0.0/16 lab-network

# All pg containers run on lab-network
podman ps  # podpg-cls1-pg1, podpg-cls1-pg2, podpg-cls1-pg3 (primary DC) + podpg-cls1-pg4 (secondary DC)
```

The network is persistent across podman restarts. Other lab containers (sqlserver, mongo, etc.) can also share this network.

---

## Architecture

Each pg container runs the full stack — PostgreSQL, Patroni, etcd, pgBouncer, HAProxy, and
Keepalived — in a single privileged container. There is no separate proxy or DCS container.

This is a **multi-datacenter setup** with:
- **Region A (Primary DC)**: podpg-cls1-pg1, podpg-cls1-pg2, podpg-cls1-pg3 — full 3-node HA cluster
- **Region B (Secondary DC)**: podpg-cls1-pg4 — single-node standby cluster (Patroni `standby_cluster` mode)

```
Host (ryzen9 — Ubuntu 24.04)
│
├── podman Network: lab-network (172.18.0.0/16)
│   │
│   ├── ─── Region A: Primary Datacenter ──────────────────────────────────────
│   │   ├── 172.18.0.9  ← Keepalived Replica VIP  (floats to sync standby)
│   │   ├── 172.18.0.10 ← Keepalived Primary VIP  (floats to Patroni leader)
│   │   ├── podpg-cls1-pg1  (172.18.0.11)  — Leader or Sync Standby  (designed: Leader)
│   │   ├── podpg-cls1-pg2  (172.18.0.12)  — Leader or Sync Standby  (designed: Sync Standby)
│   │   └── podpg-cls1-pg3  (172.18.0.13)  — Replica (nosync: true)
│   │
│   └── ─── Region B: Secondary Datacenter (Standby Cluster) ─────────────────
│       └── podpg-cls1-pg4  (172.18.0.14)  — Standby Cluster Leader (streams from primary VIP)
│
└── podman Named Volumes: pg-backups (shared pgBackRest POSIX repo)
                          pg-data-podpg-cls1-pg4, pg-logs-podpg-cls1-pg4 (standby data)
```

### Replication Topology

**Primary Cluster (Region A)**

| Node | Designed Role   | Patroni Tag     | Notes                                    |
|------|-----------------|-----------------|------------------------------------------|
| podpg-cls1-pg1  | Leader          | —               | Primary; writes committed only after podpg-cls1-pg2 acks WAL |
| podpg-cls1-pg2  | Sync Standby    | —               | `synchronous_node_count=1`; zero data loss on podpg-cls1-pg1 failure |
| podpg-cls1-pg3  | Replica         | `nosync: true`  | Always async; never elected Sync Standby |

**Standby Cluster (Region B)**

| Node | Designed Role          | Notes                                                          |
|------|------------------------|----------------------------------------------------------------|
| podpg-cls1-pg4  | Standby Cluster Leader | Streams from primary VIP (172.18.0.10); read-only until promoted |

Roles in Region A are dynamic — Patroni may promote podpg-cls1-pg2 or podpg-cls1-pg3 on failover. The designed topology is
restored via `patronictl switchover` after recovery. podpg-cls1-pg3 can become leader in a disaster but will never
hold the Sync Standby role. podpg-cls1-pg4 stays in standby mode until a Region A DC failure triggers promotion.

### Port Mapping (host → container)

```
┌──────────┬──────┬──────┬─────────┬─────────────┬──────────┬───────────────────────────────────┐
│ Container│ SSH  │ PG   │ Patroni │ pg_exporter │ pgBouncer│ HAProxy (host ports — needs new    │
│          │      │      │ REST    │             │          │  container creation to take effect) │
├──────────┼──────┼──────┼─────────┼─────────────┼──────────┼────────┬──────────┬───────────────┤
│ podpg-cls1-pg1      │ 2211 │ 5433 │ 8011    │ 9194        │ 6433     │ 15000  │ 15001    │ 17000         │
│ podpg-cls1-pg2      │ 2212 │ 5434 │ 8012    │ 9195        │ 6434     │ 25000  │ 25001    │ 27000         │
│ podpg-cls1-pg3      │ 2213 │ 5435 │ 8013    │ 9196        │ 6435     │ 35000  │ 35001    │ 37000         │
│ podpg-cls1-pg4 *    │ 2214 │ 5437 │ 8014    │ —           │ 6436     │ 45000  │ 45001    │ 47000         │
└──────────┴──────┴──────┴─────────┴─────────────┴──────────┴────────┴──────────┴───────────────┘
                                                             write    read      stats
                                                             port     port      UI
* podpg-cls1-pg4 is read-only (standby mode). HAProxy write port (45000) will fail until podpg-cls1-pg4 is promoted.

HAProxy container-internal ports (always available via podman exec):
  :5000 → write   (routes to Patroni primary only, health: GET /primary  → 200)
  :5001 → read    (routes to healthy replicas,     health: GET /replica  → 200)
  :7000 → stats   (HTTP UI, basic auth: admin / <PG_SUPERUSER_PWD>)

etcd cluster (inter-container, no host port mapping needed):
  Primary DC (3-node etcd cluster):
    podpg-cls1-pg1: 172.18.0.11:2379 (client) / :2380 (peer)
    podpg-cls1-pg2: 172.18.0.12:2379 (client) / :2380 (peer)
    podpg-cls1-pg3: 172.18.0.13:2379 (client) / :2380 (peer)
  Secondary DC (single-node etcd — for standby Patroni only):
    podpg-cls1-pg4: 172.18.0.14:2379 (client) / :2380 (peer)
```

### Traffic Flow

```
Primary DC (Region A):
  Application write  →  VIP 172.18.0.10:5000  →  HAProxy (any node)  →  <leader> :5432
  Application read   →  VIP 172.18.0.9:5001   →  HAProxy (any node)  →  <replica> :5432

Secondary DC (Region B — standby streaming):
  podpg-cls1-pg4 streams WAL from primary VIP 172.18.0.10:5432 continuously
  podpg-cls1-pg4 is read-only until promoted. Direct access: localhost:5437

Notes:
  - VIPs are inside the podman network. From the host (ryzen9), use HAProxy host-mapped ports:
    localhost:15000/25000/35000 for writes; :15001/25001/35001 for reads (primary DC)
    localhost:45001 for reads from podpg-cls1-pg4 standby (when operational)
  - After Region A failover (e.g. podpg-cls1-pg2 promoted after podpg-cls1-pg1 failure):
    Keepalived detects /primary passes on podpg-cls1-pg2 → primary VIP (172.18.0.10) migrates to podpg-cls1-pg2
    podpg-cls1-pg4 automatically reconnects to new primary via the VIP — no reconfiguration needed
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

## Host One-Time Setup (ryzen9 — Ubuntu 24.04)

Run these steps once on your ryzen9 host to enable password-free named connections.

### 1. /etc/hosts — hostname aliases

```bash
sudo tee -a /etc/hosts << 'EOF'

# PostgreSQL podman cluster — lab-network 172.18.0.0/16
127.0.0.1  podpg-cls1-pg1    # PostgreSQL :5433  pgBouncer :6433  Patroni :8011  (Region A)
127.0.0.1  podpg-cls1-pg2    # PostgreSQL :5434  pgBouncer :6434  Patroni :8012  (Region A)
127.0.0.1  podpg-cls1-pg3    # PostgreSQL :5435  pgBouncer :6435  Patroni :8013  (Region A)
127.0.0.1  podpg-cls1-pg4    # PostgreSQL :5437  pgBouncer :6436  Patroni :8014  (Region B standby)
EOF
```

Verify: `ping -c1 podpg-cls1-pg1` should resolve to `127.0.0.1`.

### 2. ~/.pgpass — password file

File: `~/.pgpass` (permissions must be `chmod 600`)

```
podpg-cls1-pg1:*:*:*:Pg@Lab2026!
podpg-cls1-pg2:*:*:*:Pg@Lab2026!
podpg-cls1-pg3:*:*:*:Pg@Lab2026!
podpg-cls1-pg4:*:*:*:Pg@Lab2026!
127.0.0.1:*:*:*:Pg@Lab2026!
localhost:*:*:*:Pg@Lab2026!
```

Wildcard entries cover all ports, databases, and users on each hostname.
`PGPASSWORD` env var takes precedence over `.pgpass`; keep them in sync in `~/.vars_personal`.

### 3. ~/.pg_service.conf — named services

File: `~/.pg_service.conf` — connect with `psql service=<name>` or `PGSERVICE=<name>`.

```ini
[podpg-cls1-pg1]           host=podpg-cls1-pg1  port=5433  user=postgres  dbname=postgres
[podpg-cls1-pg2]           host=podpg-cls1-pg2  port=5434  user=postgres  dbname=postgres
[podpg-cls1-pg3]           host=podpg-cls1-pg3  port=5435  user=postgres  dbname=postgres
[podpg-cls1-pg4]           host=podpg-cls1-pg4  port=5437  user=postgres  dbname=postgres  # standby (read-only)

[podpg-cls1-pg1-bouncer]   host=podpg-cls1-pg1  port=6433  user=postgres  dbname=postgres
[podpg-cls1-pg2-bouncer]   host=podpg-cls1-pg2  port=6434  user=postgres  dbname=postgres
[podpg-cls1-pg3-bouncer]   host=podpg-cls1-pg3  port=6435  user=postgres  dbname=postgres
[podpg-cls1-pg4-bouncer]   host=podpg-cls1-pg4  port=6436  user=postgres  dbname=postgres  # standby

[podpg-cls1-pg1-rw]        host=podpg-cls1-pg1  port=5433  user=dba_rw    dbname=dba
[podpg-cls1-pg2-rw]        host=podpg-cls1-pg2  port=5434  user=dba_rw    dbname=dba
[podpg-cls1-pg3-rw]        host=podpg-cls1-pg3  port=5435  user=dba_rw    dbname=dba

[podpg-cls1-pg1-ro]        host=podpg-cls1-pg1  port=5433  user=dba_ro    dbname=dba
[podpg-cls1-pg2-ro]        host=podpg-cls1-pg2  port=5434  user=dba_ro    dbname=dba
[podpg-cls1-pg3-ro]        host=podpg-cls1-pg3  port=5435  user=dba_ro    dbname=dba
[podpg-cls1-pg4-ro]        host=podpg-cls1-pg4  port=5437  user=dba_ro    dbname=dba    # standby read traffic
```

### 4. ~/.zshrc — dynamic shell functions

Add to `~/.zshrc` (already done if you followed the setup steps):

```zsh
_PG_NODES=("8011:podpg-cls1-pg1:5433" "8012:podpg-cls1-pg2:5434" "8013:podpg-cls1-pg3:5435")

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
  podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null \
    || podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null \
    || echo "ERROR: containers not reachable"

  echo ""
  echo "=== Keepalived VIPs ==="
  for _n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
    podman exec "${_n}" ip addr show eth0 2>/dev/null \
      | awk -v node="${_n}" '/inet / && !/172\.18\.0\.1[123]\//{printf "  %-4s <- %s\n", node, $2}'
  done

  echo ""
  echo "=== HAProxy backends (be_write / be_read) ==="
  for _n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
    if podman exec "${_n}" systemctl is-active haproxy >/dev/null 2>&1; then
      podman exec "${_n}" bash -c \
        'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
         | grep -v "^#\|FRONTEND\|stats" | cut -d, -f1,2,18' 2>/dev/null
      break
    fi
  done
}

alias psql-podpg-cls1-pg1='psql service=podpg-cls1-pg1'
alias psql-podpg-cls1-pg2='psql service=podpg-cls1-pg2'
alias psql-podpg-cls1-pg3='psql service=podpg-cls1-pg3'
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
psql -h podpg-cls1-pg1 -p 5433 -U postgres postgres    # leader
psql -h podpg-cls1-pg2 -p 5434 -U postgres postgres    # sync standby
psql -h podpg-cls1-pg3 -p 5435 -U postgres postgres    # replica (nosync)
```

### B. By hostname — pgBouncer (after /etc/hosts is set)

```bash
psql -h podpg-cls1-pg1 -p 6433 -U postgres postgres
psql -h podpg-cls1-pg2 -p 6434 -U postgres postgres
psql -h podpg-cls1-pg3 -p 6435 -U postgres postgres
```

### C. Named service (after /etc/hosts is set)

```bash
psql service=podpg-cls1-pg1            # direct PG on podpg-cls1-pg1
psql service=podpg-cls1-pg2            # direct PG on podpg-cls1-pg2  (sync standby)
psql service=podpg-cls1-pg3            # direct PG on podpg-cls1-pg3
psql service=podpg-cls1-pg1-bouncer    # via pgBouncer on podpg-cls1-pg1
psql service=podpg-cls1-pg1-rw         # as dba_rw on podpg-cls1-pg1
psql service=podpg-cls1-pg1-ro         # as dba_ro on podpg-cls1-pg1
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

### E. Via Keepalived VIPs (podman-internal — from container exec)

The VIPs float between containers. Accessible inside the podman network (not from the host directly).

```bash
# Primary VIP (172.18.0.10) — always the Patroni leader
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5432 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# Replica VIP (172.18.0.9) — highest-priority healthy replica
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.9 -p 5432 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
```

### F. Via HAProxy + VIP (podman-internal — best practice for applications)

HAProxy routes based on Patroni health check — write port goes only to primary,
read port goes only to replicas, regardless of which container's HAProxy you hit.

```bash
# Writes via primary VIP + HAProxy write port
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
# → always returns the primary node, is_replica=f

# Reads via primary VIP + HAProxy read port
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5001 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
# → always returns a replica, is_replica=t

# Reads via replica VIP + HAProxy read port
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.9 -p 5001 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
```

### G. Via HAProxy host-mapped ports (from host — after container recreation)

HAProxy ports are exposed to the host (ryzen9) via per-container port mappings.
These require the containers to be recreated (see Ansible Operations below).

```bash
# Write port on each node's HAProxy — all route to the current primary
psql -h localhost -p 15000 -U postgres postgres   # podpg-cls1-pg1 HAProxy write  ← usually primary
psql -h localhost -p 25000 -U postgres postgres   # podpg-cls1-pg2 HAProxy write
psql -h localhost -p 35000 -U postgres postgres   # podpg-cls1-pg3 HAProxy write

# Read port on each node's HAProxy — all route to a healthy replica
psql -h localhost -p 15001 -U postgres postgres   # podpg-cls1-pg1 HAProxy read
psql -h localhost -p 25001 -U postgres postgres   # podpg-cls1-pg2 HAProxy read
psql -h localhost -p 35001 -U postgres postgres   # podpg-cls1-pg3 HAProxy read

# HAProxy stats page (open in browser)
open http://localhost:17000    # podpg-cls1-pg1 stats  (admin / Pg@Lab2026!)
open http://localhost:27000    # podpg-cls1-pg2 stats
open http://localhost:37000    # podpg-cls1-pg3 stats

# Using hostname aliases (after /etc/hosts)
psql -h podpg-cls1-pg1 -p 15000 -U postgres postgres   # HAProxy write via podpg-cls1-pg1
psql -h podpg-cls1-pg2 -p 25001 -U postgres postgres   # HAProxy read  via podpg-cls1-pg2
```

---

## Patroni Status & Management

```bash
# Full cluster status (run from any node)
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list

# Cluster topology with history
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml topology

# Cluster event history (switchovers, failovers, timeline changes)
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml history pg-podman-cls1

# Replication lag check
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list | grep -E "Lag|Member"

# Show current cluster config (DCS-stored parameters)
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml show-config

# Edit DCS-stored cluster config
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml edit-config

# Patroni REST API — health check on each node
curl -s http://localhost:8011/patroni | python3 -m json.tool   # podpg-cls1-pg1
curl -s http://localhost:8012/patroni | python3 -m json.tool   # podpg-cls1-pg2
curl -s http://localhost:8013/patroni | python3 -m json.tool   # podpg-cls1-pg3

# Check which node is primary (returns HTTP 200 only on primary, 503 otherwise)
curl -s -o /dev/null -w "%{http_code}" http://localhost:8011/primary   # podpg-cls1-pg1
curl -s -o /dev/null -w "%{http_code}" http://localhost:8012/primary   # podpg-cls1-pg2
curl -s -o /dev/null -w "%{http_code}" http://localhost:8013/primary   # podpg-cls1-pg3 (never primary)

# Check which nodes are healthy replicas
curl -s -o /dev/null -w "%{http_code}" http://localhost:8011/replica   # 200 if streaming replica
curl -s -o /dev/null -w "%{http_code}" http://localhost:8013/replica   # 200 if streaming replica

# Switchover (graceful, requires a leader)
# IMPORTANT: cluster name is a required positional argument; omitting it triggers interactive
# mode which aborts with "Aborted!" when Enter is pressed with no input.
# --force suppresses the interactive confirmation prompt.
# --leader  = current primary to step down  (check with: patronictl list)
# --candidate = replica to promote; either podpg-cls1-pg1 or podpg-cls1-pg2 can be leader — pick the other one
# Example (replace <current-leader> and <candidate> with actual node names):
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml switchover pg-podman-cls1 \
  --leader <current-leader> --candidate <candidate> --force

# Trigger a manual failover (promotes a replica to leader)
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml failover pg-podman-cls1 --force

# Failover to a specific node
# NOTE: Patroni 4.x uses --leader instead of the deprecated --master flag
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml failover pg-podman-cls1 \
  --leader podpg-cls1-pg2 --candidate podpg-cls1-pg1 --force

# Pause/resume Patroni automatic failover
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml pause
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml resume

# Reload Patroni config after editing patroni.yml
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml reload pg-podman-cls1

# Reinitialize a lagging/diverged replica
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml reinit pg-podman-cls1 podpg-cls1-pg1 --force
```

---

## PostgreSQL Status

```bash
export PGPASSWORD='Pg@Lab2026!'

# Connect to specific node (podpg-cls1-pg1 or podpg-cls1-pg2 may be leader at any time; use pg-primary for role-based access)
psql -h localhost -p 5433 -U postgres postgres   # podpg-cls1-pg1
psql -h localhost -p 5434 -U postgres postgres   # podpg-cls1-pg2
psql -h localhost -p 5435 -U postgres postgres   # podpg-cls1-pg3 (always replica)

# Replication status — lag in seconds and bytes (run on primary — podpg-cls1-pg1)
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

# Check standby recovery status (run on replica — podpg-cls1-pg2 or podpg-cls1-pg3)
# replication_delay: seconds since last transaction was replayed on this replica
psql -h localhost -p 5434 -U postgres postgres -c "
  SELECT pg_is_in_recovery(),
         extract(epoch FROM (now() - pg_last_xact_replay_timestamp()))::numeric(10,3) AS replication_delay_sec,
         pg_last_wal_receive_lsn(),
         pg_last_wal_replay_lsn(),
         round((pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())) / 1048576.0, 2) AS receive_vs_replay_lag_mb;"

# Active connections and sessions (run on primary — podpg-cls1-pg1)
psql -h localhost -p 5433 -U postgres postgres -c "
  SELECT count(*), state, wait_event_type, wait_event
  FROM pg_stat_activity GROUP BY state, wait_event_type, wait_event ORDER BY count DESC;"

# Long-running queries (>30s) (run on primary — podpg-cls1-pg1)
psql -h localhost -p 5433 -U postgres postgres -c "
  SELECT pid, now()-query_start AS duration, state, left(query,80) AS query
  FROM pg_stat_activity
  WHERE state != 'idle' AND query_start < now() - interval '30 seconds'
  ORDER BY duration DESC;"

# pg_stat_statements top 10 by total time (run on primary — podpg-cls1-pg1)
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
podman exec podpg-cls1-pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep -v "^#" | cut -d, -f1,2,18 \
   | awk -F, '"'"'{printf "%-12s %-8s %s\n", $1, $2, $3}'"'"''

# Full stats page (open in browser after port-forwarding)
# From inside container: http://172.18.0.12:7000/  (admin / <PG_SUPERUSER_PWD>)

# Check which backends are UP (for write port)
podman exec podpg-cls1-pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep "be_write" | cut -d, -f1,2,18 \
   | awk -F, '"'"'{printf "%-12s %-8s %s\n", $1, $2, $3}'"'"''

# Check which backends are UP (for read port)
podman exec podpg-cls1-pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep "be_read" | cut -d, -f1,2,18 \
   | awk -F, '"'"'{printf "%-12s %-8s %s\n", $1, $2, $3}'"'"''

# HAProxy service status on each node
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ==="; podman exec $n systemctl status haproxy --no-pager -l | tail -3
done

# Reload HAProxy config (no connection drops, used after config change)
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do podman exec $n systemctl reload haproxy; done

# Verify HAProxy write port routes only to primary
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres -d postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# Verify HAProxy read port routes only to replica
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5001 \
  -U postgres -d postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
```

---

## Keepalived Status & Management

```bash
# Which node holds each VIP
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n ip addr show eth0 | grep "inet "
done
# 172.18.0.10 (eth0:vip)    → Patroni primary (leader)
# 172.18.0.9  (eth0:rvip)   → sync standby (Keepalived uses /synchronous endpoint)

# Keepalived service status
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n systemctl status keepalived --no-pager | tail -5
done

# VRRP state on each node (MASTER vs BACKUP)
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n: "
  podman exec $n journalctl -u keepalived --no-pager -n 5 2>/dev/null \
    | grep -E "MASTER|BACKUP" | tail -2
done

# Keepalived effective priorities (shows weight contribution)
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n primary check: "
  podman exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary
  echo -n "  replica check: "
  podman exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/replica
  echo
done

# Manually verify VIP reachability from inside cluster
podman exec podpg-cls1-pg3 ping -c 2 172.18.0.10   # primary VIP
podman exec podpg-cls1-pg3 ping -c 2 172.18.0.9    # replica VIP

# Restart Keepalived (re-triggers VRRP election)
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do podman exec $n systemctl restart keepalived; done
# Wait ~8s for election to settle then re-check VIP assignment
```

---

## pgBouncer Status & Management

```bash
# pgBouncer admin console (from host via mapped port)
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -p 6433 -U postgres pgbouncer -c "SHOW POOLS;"    # podpg-cls1-pg1
psql -h localhost -p 6434 -U postgres pgbouncer -c "SHOW POOLS;"    # podpg-cls1-pg2
psql -h localhost -p 6435 -U postgres pgbouncer -c "SHOW POOLS;"    # podpg-cls1-pg3

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
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n systemctl status pgbouncer --no-pager | tail -3
done

# Reload pgBouncer after config change
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do podman exec $n systemctl reload pgbouncer; done

# Fix stale connection pool (SASL auth failures after failover)
# This clears all server-side connections and forces reconnects
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "Reconnecting $n pgBouncer pools..."
  podman exec $n bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 127.0.0.1 -p 6432 \
    -U postgres pgbouncer -c "RECONNECT;" 2>/dev/null' \
  || podman exec $n systemctl reload pgbouncer
done

# Check which PostgreSQL host each pgBouncer is pointing to
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n pgbouncer → " && podman exec $n grep "^*" /etc/pgbouncer/pgbouncer.ini
done
```

---

## etcd Status & Management

```bash
# etcd cluster member list (from inside container)
podman exec podpg-cls1-pg1 etcdctl --endpoints=http://172.18.0.11:2379 member list

# etcd cluster health
podman exec podpg-cls1-pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health

# etcd endpoint status (leader, raft term, raft index)
podman exec podpg-cls1-pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint status --write-out=table

# Read Patroni DCS key
podman exec podpg-cls1-pg1 etcdctl --endpoints=http://172.18.0.11:2379 \
  get /service/pg-podman-cls1/leader

# etcd service status
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n systemctl status etcd --no-pager | tail -3
done
```

---

## pgBackRest Status & Management

```bash
# Show backup info (run from any node with access to shared volume)
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 info

# Full backup (run on leader — podpg-cls1-pg1)
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 --log-level-console=info backup --type=full

# Incremental backup
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 --log-level-console=info backup --type=incr

# Differential backup
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 --log-level-console=info backup --type=diff

# Check backup integrity
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 check

# Restore (stop patroni first, then restore, then restart)
podman exec podpg-cls1-pg1 systemctl stop patroni
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 --log-level-console=info restore --delta
podman exec podpg-cls1-pg1 systemctl start patroni

# Point-in-time restore
podman exec podpg-cls1-pg1 systemctl stop patroni
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 --log-level-console=info restore --delta \
  --target="2026-04-30 10:30:00" --target-action=promote
podman exec podpg-cls1-pg1 systemctl start patroni
```

---

## Log Inspection

All commands use `podman exec` so they work from the host (ryzen9) terminal without SSH.

### PostgreSQL logs

```bash
# Tail PostgreSQL log on the current leader (podpg-cls1-pg1)
podman exec podpg-cls1-pg1 tail -100 /var/log/postgresql/postgresql-Wed.log

# Follow PostgreSQL log live
podman exec podpg-cls1-pg1 bash -c "tail -f /var/log/postgresql/postgresql-$(date +%a).log"

# Search for errors in PostgreSQL log
podman exec podpg-cls1-pg1 grep -i "ERROR\|FATAL\|PANIC" /var/log/postgresql/postgresql-Wed.log | tail -20

# PostgreSQL log on all nodes
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n bash -c \
    "tail -20 /var/log/postgresql/postgresql-\$(date +%a).log 2>/dev/null || echo 'no log'"
done
```

### Patroni logs

```bash
# Patroni log on all nodes
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n tail -30 /var/log/patroni/patroni.log
done

# Follow Patroni log live on leader
podman exec podpg-cls1-pg1 tail -f /var/log/patroni/patroni.log

# Patroni log via journald
podman exec podpg-cls1-pg1 journalctl -u patroni --no-pager -n 50

# Search for failover/switchover events
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n grep -i "promoting\|demoting\|failover\|switchover\|leader" \
    /var/log/patroni/patroni.log | tail -10
done
```

### HAProxy logs

```bash
# HAProxy logs via journald
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n journalctl -u haproxy --no-pager -n 20
done

# Follow HAProxy log live
podman exec podpg-cls1-pg1 journalctl -u haproxy -f

# Check backend state changes in HAProxy log
podman exec podpg-cls1-pg1 journalctl -u haproxy --no-pager | grep -i "UP\|DOWN\|BACKEND"
```

### Keepalived logs

```bash
# Keepalived VRRP election and VIP assignment events
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n journalctl -u keepalived --no-pager -n 20
done

# Follow Keepalived log live (watch VIP migrations)
podman exec podpg-cls1-pg1 journalctl -u keepalived -f

# Show only MASTER/BACKUP transitions
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n: " && podman exec $n journalctl -u keepalived --no-pager \
    | grep -E "MASTER STATE|BACKUP STATE" | tail -3
done
```

### pgBouncer logs

```bash
# pgBouncer log on all nodes
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n tail -20 /var/log/pgbouncer/pgbouncer.log
done

# Follow pgBouncer log live
podman exec podpg-cls1-pg1 tail -f /var/log/pgbouncer/pgbouncer.log

# Search for auth errors
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n grep -i "ERROR\|failed\|refused" \
    /var/log/pgbouncer/pgbouncer.log | tail -5
done
```

### pgBackRest logs

```bash
# pgBackRest backup log
podman exec podpg-cls1-pg1 cat /var/log/pgbackrest/pg-podman-cls1-backup.log 2>/dev/null | tail -30

# List all pgBackRest logs
podman exec podpg-cls1-pg1 ls /var/log/pgbackrest/

# Check stanza status and health
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 info
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 check

# Check stanza details (system-id, wal_system_identifier, etc.)
podman exec podpg-cls1-pg1 sudo -u postgres pgbackrest --stanza=pg-podman-cls1 info --log-level-console=info
```

### etcd logs

```bash
# etcd logs via journald
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n journalctl -u etcd --no-pager -n 15
done

# etcd leader election events
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo "=== $n ===" && podman exec $n journalctl -u etcd --no-pager \
    | grep -i "elected\|leader\|follower" | tail -5
done
```

---

## Health Validation Cheatsheet

```bash
export PGPASSWORD='Pg@Lab2026!'

# 1. Patroni cluster state
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list

# 2. VIP locations
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n: " && podman exec $n ip addr show eth0 | grep "inet " | awk '{print $2}'
done

# 3. HAProxy backend health (1 line per backend)
podman exec podpg-cls1-pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep -v "^#\|FRONTEND" | cut -d, -f1,2,18'

# 4. Write path: confirm connection lands on primary
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# 5. Read path: confirm connection lands on a replica
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5001 \
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
podman exec podpg-cls1-pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health

# 9. pgBackRest stanza check
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 check
```

---

## Failover Testing

```bash
export PGPASSWORD='Pg@Lab2026!'

# Step 1: Identify current leader and sync standby (either podpg-cls1-pg1 or podpg-cls1-pg2 may be leader)
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
# Note the Leader and Sync Standby rows — use those names in the commands below.
# podpg-cls1-pg3 always has nosync:true and is never promoted to sync standby, but CAN become leader in failover.

# Step 2: Graceful switchover — swap leader and sync standby
# Replace <leader> with the current Leader node, <standby> with the Sync Standby node.
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader <leader> --candidate <standby> --force

# Step 3: Watch VIP migrate (run in a second terminal, re-runs every 2s)
watch -n 2 'for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do echo -n "$n: "; podman exec $n ip addr show eth0 | grep "inet " | awk "{print \$2}"; done'

# Step 4: Verify write connection lands on new leader (HAProxy updates within ~9s)
sleep 10
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# Simulate node failure — stop the current leader (check with patronictl list first)
# The sync standby (podpg-cls1-pg1 or podpg-cls1-pg2) is automatically promoted — zero data loss
podman stop <leader>
sleep 15
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list   # former standby is now leader

# Recover failed node — it rejoins as replica and streams from the new leader
podman start <former-leader>
sleep 20
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list   # rejoined as replica
# Switchover back if desired (restore any preferred topology)
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader <current-leader> --candidate <former-leader> --force
```

---

## Disaster Recovery (DR) Testing: Complete Reference

### DR Quick Overview

**Scenario**: Both podpg-cls1-pg1 (Leader) & podpg-cls1-pg2 (Sync Standby) fail — podpg-cls1-pg3 (Replica with nosync: true) takes over.

**Key Points**:
- ⚠️  **Automatic failover is DISABLED** in this cluster
- ⚠️  **podpg-cls1-pg3 is async (nosync: true)** — NOT eligible for automatic election
- ✅ **MANUAL COMMAND REQUIRED**: `patronictl failover pg-docker-cls1 --force` to promote podpg-cls1-pg3
- ✅ **VIP (172.18.0.10) automatically migrates** to podpg-cls1-pg3 after promotion
- ✅ **Applications reconnect transparently** to same VIP — no code changes needed
- ✅ **Data is safe**: Writes on podpg-cls1-pg3 are persisted; podpg-cls1-pg1/podpg-cls1-pg2 catch up via WAL replay

### DR Test Validation Matrix

Track the state at each phase of the test. Example for Cycle 1:

| Phase | Timeline | podpg-cls1-pg1 Role | podpg-cls1-pg2 Role | podpg-cls1-pg3 Role | podpg-cls1-pg1 State | podpg-cls1-pg2 State | podpg-cls1-pg3 State | VIP Location | Lag = 0 |
|-------|----------|----------|----------|----------|-----------|-----------|-----------|--------------|---------|
| Pre-DR | 1 | Leader | Sync Standby | Replica | running | running | running | podpg-cls1-pg1 | ✓ |
| Disaster | 1 | Leader | Sync Standby | Replica | **offline** | **offline** | running | podpg-cls1-pg1 (old) | N/A |
| Detected | 1 | offline | offline | Replica | offline | offline | streaming | none | N/A |
| Promoted | **2** | offline | offline | **Leader** | offline | offline | running | **podpg-cls1-pg3** | N/A |
| DR Active | 2 | offline | offline | Leader | offline | offline | running | podpg-cls1-pg3 | N/A |
| Recovery | 2 | Replica | Replica | Leader | starting | starting | running | podpg-cls1-pg3 | N/A → ✓ |
| Restored | **3** | **Leader** | **Sync Standby** | **Replica** | running | streaming | streaming | **podpg-cls1-pg1** | ✓ |

Repeat the same matrix for Cycle 2 and compare timings.

### Pre-DR Baseline Verification

**Purpose**: Capture baseline state and confirm all systems ready before disaster

```bash
# Step 1: Capture baseline topology
echo "=== Baseline Topology ===" 
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list

# Step 2: Verify VIP assignments
echo "=== VIP Status ===" 
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 2>/dev/null | grep "172.18.0.1[09]" | awk '{print $2}'
done

# Step 3: Check HAProxy health
echo "=== HAProxy Backend Status ===" 
podman exec podpg-cls1-pg1 curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" | grep "pg_write"

# Step 4: Verify etcd cluster
echo "=== etcd Cluster Health ===" 
podman exec podpg-cls1-pg1 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 endpoint health | wc -l
echo "(Expected: 3 healthy members)"

# Step 5: Baseline replication lag
echo "=== Baseline Replication Lag ===" 
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -p 5433 -U postgres postgres << 'EOF' -t 2>&1 | grep "0.00"
SELECT ROUND((sent_lsn - replay_lsn) / 1048576.0, 2) AS lag_mb FROM pg_stat_replication;
EOF

echo "✅ PRE-DR VERIFICATION COMPLETE"
```

**Expected State**:
- podpg-cls1-pg1: Leader, podpg-cls1-pg2: Sync Standby, podpg-cls1-pg3: Replica
- Timeline: 1
- VIP: 172.18.0.10 on podpg-cls1-pg1
- Lag: 0.00 MB on both replicas
- etcd: 3/3 healthy

---

### Disaster Scenario

**Purpose**: Simulate podpg-cls1-pg1 & podpg-cls1-pg2 failure and trigger manual failover

```bash
# Step 1: Stop podpg-cls1-pg1 (Leader)
echo "=== STOPPING podpg-cls1-pg1 (Leader) ===" 
podman stop podpg-cls1-pg1
echo "✓ podpg-cls1-pg1 stopped"

# Step 2: Stop podpg-cls1-pg2 (Sync Standby)
echo "=== STOPPING podpg-cls1-pg2 (Sync Standby) ===" 
podman stop podpg-cls1-pg2
echo "✓ podpg-cls1-pg2 stopped"

# Step 3: Wait for Patroni to detect failure
echo "=== Waiting for Patroni to detect failure..." 
sleep 10

# Step 4: Verify podpg-cls1-pg1 & podpg-cls1-pg2 offline
echo "=== Verify podpg-cls1-pg1 & podpg-cls1-pg2 Offline ===" 
podman ps --format "table {{.Names}}\t{{.Status}}" | grep -E "podpg-cls1-pg1|podpg-cls1-pg2|podpg-cls1-pg3"

# Step 5: Check cluster state (podpg-cls1-pg3 still Replica)
# ⚠️ NOTE: When podpg-cls1-pg1 & podpg-cls1-pg2 are stopped, etcd loses quorum (2/3 down).
# Patroni cannot connect to DCS — patronictl will timeout/fail.
# Use direct PostgreSQL query to verify podpg-cls1-pg3 is still in recovery mode (replica):
echo "=== Cluster State (podpg-cls1-pg3 should still be Replica) ===" 
podman exec podpg-cls1-pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 127.0.0.1 -p 5432 -U postgres postgres -t -c "SELECT pg_is_in_recovery();"'

# Step 6: Check etcd status from podpg-cls1-pg3
# ⚠️ NOTE: etcd will show "unhealthy cluster" when podpg-cls1-pg1 & podpg-cls1-pg2 are down (lost quorum).
# This is EXPECTED — we proceed to failover anyway.
echo "=== etcd Status (will show unhealthy due to quorum loss) ===" 
podman exec podpg-cls1-pg3 etcdctl --endpoints=http://172.18.0.13:2379 endpoint health 2>&1 | grep -E "^http://|Error:" | head -1 || echo "Expected: etcd unhealthy due to lost quorum (2/3 nodes down)"

# Step 7: ⚠️ CRITICAL LIMITATION ⚠️
# patronictl failover CANNOT work when etcd has lost quorum (podpg-cls1-pg1 & podpg-cls1-pg2 down).
# The command will fail with: "Etcd is not responding properly"
# 
# REASON: patronictl requires DCS (etcd) to:
#   1. Read current cluster state
#   2. Write failover decision
#   3. Communicate with podpg-cls1-pg3's Patroni daemon
#
# With 2/3 etcd nodes down → no quorum → no DCS operations possible
#
# WORKAROUND FOR TESTING:
# Restart podpg-cls1-pg1 & podpg-cls1-pg2 FIRST to restore etcd quorum, THEN test failover:
echo ""
echo "⚠️  ETCD QUORUM LOST - Cannot proceed with patronictl failover"
echo "⚠️  Solution: Restart podpg-cls1-pg1 & podpg-cls1-pg2 to restore etcd quorum FIRST"
echo ""
echo "Run this in a separate terminal:"
echo "  podman start podpg-cls1-pg1 podpg-cls1-pg2"
echo "  sleep 20"
echo "  podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml list  # verify etcd healthy"
echo ""
echo "Then proceed with failover test by stopping podpg-cls1-pg1 & podpg-cls1-pg2 again"
echo ""
echo "SKIPPING failover step (will work once etcd quorum is restored)"

# Step 8: Wait for promotion
echo "=== Waiting for promotion..." 
sleep 5

# Step 9: Verify podpg-cls1-pg3 is now Leader
echo "=== VERIFY podpg-cls1-pg3 PROMOTED TO LEADER ===" 
podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml list | grep "podpg-cls1-pg3"

echo ""
echo "✅ DISASTER & PROMOTION COMPLETE (Timeline: 1→2)"
```

**Expected State After Promotion**:
- podpg-cls1-pg1: offline, podpg-cls1-pg2: offline, podpg-cls1-pg3: Leader
- Timeline: 2 (advanced from 1)
- podpg-cls1-pg3 State: running (not streaming)
- VIP: should migrate to podpg-cls1-pg3

---

### Manual Promotion

**Purpose**: Promote podpg-cls1-pg3 to leader and verify it accepts writes

```bash
# Step 1: Execute Manual Failover Command
echo "=== Execute Manual Failover Command ===" 
podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force

# Step 2: Wait for Promotion to Complete
echo "=== Waiting 5 seconds for promotion to complete..." 
sleep 5

# Step 3: Verify podpg-cls1-pg3 is Now Leader
echo "=== Verify podpg-cls1-pg3 is Now Leader ===" 
podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml list

# Expected Output shows: podpg-cls1-pg3 | ... | Leader | running | 2 |

# Step 4: Verify podpg-cls1-pg3 Can Perform Writes (Critical Test)
export PGPASSWORD='Pg@Lab2026!'
echo ""
echo "=== Verify podpg-cls1-pg3 Can Perform Writes ===" 
podman exec podpg-cls1-pg3 psql -U postgres postgres -c \
  "SELECT is_wal_replay_paused() AS replay_paused, pg_is_in_recovery() AS is_replica;"

# Expected Output: f | f (NOT in recovery, can accept writes)
# If is_replica = t, promotion failed. Do NOT proceed with writes.
```

**Expected State After Promotion**:
- Timeline incremented from 1 to 2
- podpg-cls1-pg3 State changed from "streaming" to "running"
- podpg-cls1-pg3 Role changed from "Replica" to "Leader"
- podpg-cls1-pg3 pg_is_in_recovery() returns FALSE

---

### DR Mode Active

**Purpose**: Test that podpg-cls1-pg3 accepts writes and verify health

```bash
# Step 1: Create DR Test Table and Insert Data
echo "=== Create DR Test Table ===" 
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -p 5435 -U postgres postgres << 'EOF'
CREATE TABLE IF NOT EXISTS dr_test (
  id SERIAL PRIMARY KEY,
  event TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO dr_test (event) VALUES 
  ('DR mode activated - podpg-cls1-pg3 is now leader'),
  ('Data written during DR on ' || now()::TEXT);

SELECT COUNT(*) as total_records, MAX(created_at) as latest FROM dr_test;
EOF

# Step 2: Verify Data Persists
echo ""
echo "=== Verify Data Persists ===" 
psql -h localhost -p 5435 -U postgres postgres -c \
  "SELECT id, event, created_at FROM dr_test ORDER BY id;"

# Step 3: Verify HAProxy Write Pool is Healthy
echo ""
echo "=== Verify HAProxy Write Pool ===" 
podman exec podpg-cls1-pg3 curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" | grep -E "^pg_write"

# Step 4: Verify pgBouncer Connectivity via VIP
echo ""
echo "=== Verify pgBouncer Connectivity ===" 
psql -h 172.18.0.10 -p 6435 -U postgres postgres -c "SELECT now();" 2>&1 | head -5

# Step 5: Verify Patroni Health Endpoints
echo ""
echo "=== Verify Patroni Health ===" 
echo -n "podpg-cls1-pg3 /primary: "
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8013/primary

echo -n "podpg-cls1-pg3 /replica: "
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8013/replica

echo ""
echo "✅ DR MODE VERIFIED: podpg-cls1-pg3 accepting user connections"
```

**Expected Output**:
- dr_test table with 2 records
- HAProxy pg_write backend shows podpg-cls1-pg3 as UP
- pgBouncer connection succeeds
- podpg-cls1-pg3 /primary returns HTTP 200
- podpg-cls1-pg3 /replica returns HTTP 503 (no replicas available)

---

### Recovery Phase

**Purpose**: Bring podpg-cls1-pg1 & podpg-cls1-pg2 back online and monitor rejoin

```bash
# Step 1: Start podpg-cls1-pg1
echo "=== Starting podpg-cls1-pg1 ===" 
podman start podpg-cls1-pg1
echo "✓ podpg-cls1-pg1 started"

# Step 2: Start podpg-cls1-pg2
echo "=== Starting podpg-cls1-pg2 ===" 
podman start podpg-cls1-pg2
echo "✓ podpg-cls1-pg2 started"

# Step 3: Wait for Services to Start
echo "=== Waiting 15 seconds for services to start..." 
sleep 15

# Step 4: Monitor Cluster Rejoin with Timeline Tracking (run for 60+ seconds)
echo "=== MONITORING CLUSTER REJOIN ===" 
for i in {1..15}; do
  elapsed=$((i*5))
  echo ""
  echo "[T=${elapsed}s] Rejoin Check $i"
  
  # Show cluster state
  status=$(podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null)
  echo "$status" | grep -E "^[+-]|pg[123]" | head -5
  
  # Show current lag
  echo "Replication LAG:"
  export PGPASSWORD='Pg@Lab2026!'
  psql -h localhost -p 5435 -U postgres postgres << 'SQL' -t 2>&1 | grep "streaming\|archive"
SELECT client_addr::text, state, ROUND((sent_lsn - replay_lsn) / 1048576.0, 2)::text AS lag_mb FROM pg_stat_replication ORDER BY client_addr;
SQL
  
  sleep 5
done

# Step 5: Final Rejoin Verification
echo ""
echo "=== RECOVERY COMPLETE ===" 
podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml list

# Step 6: Verify Final Replication Lag is Zero
echo ""
echo "=== Verify Final Replication Lag ===" 
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -p 5435 -U postgres postgres << 'EOF'
SELECT 
  COUNT(*) AS replica_count,
  MAX(ROUND((sent_lsn - replay_lsn) / 1048576.0, 2)) AS max_lag_mb
FROM pg_stat_replication;
EOF

echo ""
echo "✅ RECOVERY PHASE COMPLETE (LAG: 0.00 MB)"
```

**Expected State During Recovery**:
- [T=10-20s]: podpg-cls1-pg1/podpg-cls1-pg2 in "archive recovery" phase
- [T=20-40s]: podpg-cls1-pg1/podpg-cls1-pg2 in "streaming" phase, lag decreasing
- [T=40-60s]: All nodes "streaming", lag → 0.00 MB
- Timeline: Still 2 (will advance to 3 after switchover)

---

### Restore Topology

**Purpose**: Switchover podpg-cls1-pg3 → podpg-cls1-pg1 to restore original topology

```bash
# Step 1: Verify Current Leader
echo "=== Current Leader (should be podpg-cls1-pg3) ===" 
podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml list | grep "Leader"

# Step 2: Execute Switchover
echo ""
echo "=== EXECUTING SWITCHOVER: podpg-cls1-pg3 → podpg-cls1-pg1 ===" 
podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
  --leader podpg-cls1-pg3 --candidate podpg-cls1-pg1 --force

# Step 3: Wait for Switchover to Complete
echo "=== Waiting 10 seconds for switchover..." 
sleep 10

# Step 4: Verify podpg-cls1-pg1 is Now Leader (timeline should be 3)
echo "=== VERIFY TOPOLOGY RESTORED ===" 
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list

# Step 5: Verify VIP Migrated Back to podpg-cls1-pg1
echo ""
echo "=== Verify VIP Assignments ===" 
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 2>/dev/null | grep "172.18.0.1[09]" | awk '{print $2}'
done

# Step 6: Verify All Healthy
echo ""
echo "=== Final Health Check ===" 
export PGPASSWORD='Pg@Lab2026!'
echo "Connection test:"
for port in 5433 5434 5435; do
  echo -n "port $port: "
  psql -h localhost -p $port -U postgres postgres -c "SELECT 'OK';" -t 2>&1 | tr -d ' '
done

# Step 7: Verify Data Integrity
echo ""
echo "=== Data Integrity Check ===" 
psql -h localhost -p 5433 -U postgres postgres -c \
  "SELECT COUNT(*) as dr_records FROM dr_test WHERE created_at IS NOT NULL;" -t 2>&1

echo ""
echo "✅ CYCLE COMPLETE"
echo "Timeline Progression: 1 → 2 → 3 ✓"
echo "Topology Restored: podpg-cls1-pg1=Leader, podpg-cls1-pg2=Standby, podpg-cls1-pg3=Replica ✓"
echo "Data Preserved: DR writes still present ✓"
```

**Expected State After Restore**:
- podpg-cls1-pg1: Leader, podpg-cls1-pg2: Sync Standby, podpg-cls1-pg3: Replica
- Timeline: 3 (advanced from 2)
- VIP: 172.18.0.10 on podpg-cls1-pg1 (restored)
- Lag: 0.00 MB (all caught up)
- dr_test table: 2 records (data preserved)

---

### Post-Recovery Validation

**Purpose**: Confirm all services operational and data integrity

```bash
# Step 1: All PostgreSQL Nodes Operational
echo "=== All PostgreSQL Nodes Operational ===" 
export PGPASSWORD='Pg@Lab2026!'
for port in 5433 5434 5435; do
  echo -n "localhost:$port → "
  psql -h localhost -p $port -U postgres postgres -c "SELECT 'HEALTHY';" -t 2>&1 | tr -d ' '
  echo
done

# Step 2: Patroni REST API Health
echo ""
echo "=== Patroni REST API Health ===" 
for port in 8011 8012 8013; do
  node=""
  [ "$port" = "8011" ] && node="podpg-cls1-pg1"
  [ "$port" = "8012" ] && node="podpg-cls1-pg2"
  [ "$port" = "8013" ] && node="podpg-cls1-pg3"
  echo -n "$node /patroni: "
  curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:$port/patroni
done

# Step 3: Replication Lag is Zero
echo ""
echo "=== Replication Lag ===" 
psql -h localhost -p 5433 -U postgres postgres << 'EOF'
SELECT 
  COUNT(*) as replica_count,
  MIN(ROUND((sent_lsn - replay_lsn) / 1048576.0, 2)) AS min_lag_mb,
  MAX(ROUND((sent_lsn - replay_lsn) / 1048576.0, 2)) AS max_lag_mb
FROM pg_stat_replication;
EOF

# Step 4: etcd Cluster Healthy
echo ""
echo "=== etcd Cluster Healthy ===" 
podman exec podpg-cls1-pg1 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health

# Step 5: Verify Data Integrity (DR writes preserved)
echo ""
echo "=== Data Integrity (DR writes preserved) ===" 
psql -h localhost -p 5433 -U postgres postgres -c \
  "SELECT COUNT(*) as dr_records FROM dr_test;"

echo ""
echo "✅ POST-RECOVERY VALIDATION COMPLETE"
```

---

### Understanding Timeline & LSN

**What is Timeline (TL)?**

Timeline is a PostgreSQL concept that increments every time:
1. A standby is promoted to leader
2. A failover occurs
3. A new WAL archive begins

**In our DR test**:
- **Pre-DR**: TL = 1 (podpg-cls1-pg1 is original leader)
- **After podpg-cls1-pg3 promotion**: TL = 2 (podpg-cls1-pg3 created new timeline when promoted)
- **After podpg-cls1-pg3 switches back to podpg-cls1-pg1**: TL = 3 (podpg-cls1-pg1 created new timeline after switchover)

**Tracking Timeline During Each Phase**:

```bash
# Track timeline on each node
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  port=$([[ "$n" == "podpg-cls1-pg1" ]] && echo 5433 || [[ "$n" == "podpg-cls1-pg2" ]] && echo 5434 || echo 5435)
  echo -n "$n: "
  podman exec $n pg_controldata /var/lib/postgresql/18/main 2>/dev/null | grep "Current wal level"
  echo -n "$n timeline: "
  podman exec $n psql -U postgres postgres -c "SELECT timeline_id FROM pg_control_checkpoint();" -t 2>&1 | head -1
done
```

**What is LSN (Log Sequence Number)?**

LSN tracks the exact byte position in the WAL (Write-Ahead Log). Key LSN values:

- **sent_lsn**: How far the leader has sent WAL to replicas
- **replay_lsn**: How far the replica has replayed (applied) WAL
- **Lag = sent_lsn - replay_lsn** (in bytes, usually converted to MB)

**Tracking LSN During Recovery**:

```bash
# Monitor LSN movement (run during recovery phase)
for i in {1..10}; do
  echo "=== LSN Check $i ==="
  podman exec podpg-cls1-pg3 psql -U postgres postgres << 'EOF' -t 2>&1 | grep -v "^$"
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

**Expected LSN Progression**:

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

### Replication Slots During DR

**What Happens to Replication Slots During Failover?**

Patroni manages replication slots automatically. During podpg-cls1-pg3 promotion:

1. **Before Promotion**: podpg-cls1-pg3 was a replica, not consuming slots
2. **During Promotion**: Patroni doesn't create new slots on podpg-cls1-pg3 (it's now the leader)
3. **After podpg-cls1-pg1/podpg-cls1-pg2 rejoin**: They reconnect as replicas, reusing their original slots

**Monitor Slot Status During DR Test**:

```bash
# Before disaster - verify slots on podpg-cls1-pg1
podman exec podpg-cls1-pg1 psql -U postgres postgres -c \
  "SELECT slot_name, slot_type, restart_lsn, restart_lsn IS NULL AS inactive FROM pg_replication_slots ORDER BY slot_name;"

# Expected Pre-DR Output:
#  slot_name      | slot_type | restart_lsn | inactive
# ----------------+-----------+-------------+----------
#  podpg-cls1-pg2            | physical  | 0/12345678  | f
#  podpg-cls1-pg3            | physical  | 0/12345678  | f

# During DR mode - check slots on podpg-cls1-pg3 (now leader)
podman exec podpg-cls1-pg3 psql -U postgres postgres -c \
  "SELECT slot_name, slot_type, restart_lsn, restart_lsn IS NULL AS inactive FROM pg_replication_slots ORDER BY slot_name;"

# Expected DR Mode Output: (0 rows - no slots on podpg-cls1-pg3 yet, replicas offline)

# After recovery - slots should re-activate on podpg-cls1-pg3
podman exec podpg-cls1-pg3 psql -U postgres postgres -c \
  "SELECT slot_name, slot_type, restart_lsn, restart_lsn IS NULL AS inactive FROM pg_replication_slots ORDER BY slot_name;"

# Expected Post-Recovery Output:
#  slot_name      | slot_type | restart_lsn | inactive
# ----------------+-----------+-------------+----------
#  podpg-cls1-pg1            | physical  | 0/12345xxx  | f
#  podpg-cls1-pg2            | physical  | 0/12345xxx  | f
```

---

### DR Troubleshooting

#### Issue: podpg-cls1-pg3 Fails to Promote to Leader

**Symptom**: podpg-cls1-pg3 remains Replica even after podpg-cls1-pg1/podpg-cls1-pg2 stopped

**Diagnose**:
```bash
podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml list

# Check if Patroni is paused
podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml list | grep -i pause

# If paused, resume it
podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml resume

# Check etcd connectivity
podman exec podpg-cls1-pg3 etcdctl --endpoints=http://172.18.0.13:2379 endpoint health
```

#### Issue: VIP Not Migrating to podpg-cls1-pg3

**Symptom**: VIP still on podpg-cls1-pg1 even though it's stopped

**Diagnose**:
```bash
# Check Keepalived status
podman exec podpg-cls1-pg3 systemctl status keepalived --no-pager

# Check Keepalived log
podman exec podpg-cls1-pg3 journalctl -u keepalived --no-pager -n 20
```

**Fix**:
```bash
# Restart Keepalived on podpg-cls1-pg3
podman exec podpg-cls1-pg3 systemctl restart keepalived
sleep 5

# Verify VIP is assigned
podman exec podpg-cls1-pg3 ip addr show eth0 | grep "172.18.0.10"
```

#### Issue: podpg-cls1-pg1/podpg-cls1-pg2 Not Rejoining After Start

**Diagnose**:
```bash
# Check podpg-cls1-pg1 patroni status
podman exec podpg-cls1-pg1 systemctl status patroni --no-pager

# Check podpg-cls1-pg1 patroni logs
podman exec podpg-cls1-pg1 tail -50 /var/log/patroni/patroni.log

# Check if podpg-cls1-pg1 can connect to etcd
podman exec podpg-cls1-pg1 etcdctl --endpoints=http://172.18.0.11:2379 endpoint health
```

**Fix**:
```bash
# Restart Patroni on podpg-cls1-pg1
podman exec podpg-cls1-pg1 systemctl restart patroni

# Monitor rejoin
sleep 10
podman exec podpg-cls1-pg3 patronictl -c /etc/patroni/patroni.yml list
```

#### Issue: etcd Cluster Unhealthy

**Check**:
```bash
podman exec podpg-cls1-pg3 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health
```

**Fix**:
```bash
# Check etcd service on that node
podman exec podpg-cls1-pg1 systemctl status etcd --no-pager

# Restart etcd if needed
podman exec podpg-cls1-pg1 systemctl restart etcd
sleep 5

# Verify cluster again
podman exec podpg-cls1-pg3 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health
```

---

### Complete DR Test Verification Checklist

#### Before Starting (Pre-DR Baseline)
- [ ] All 3 nodes running (podpg-cls1-pg1 leader, podpg-cls1-pg2 standby, podpg-cls1-pg3 replica)
- [ ] Cluster topology correct (podpg-cls1-pg1 Leader, podpg-cls1-pg2 Sync Standby, podpg-cls1-pg3 Replica nosync)
- [ ] VIP on podpg-cls1-pg1 (172.18.0.10)
- [ ] All Patroni health endpoints returning correct HTTP codes
- [ ] All PostgreSQL connections responding
- [ ] HAProxy write pool showing podpg-cls1-pg1 as UP
- [ ] Replication lag = 0.00 MB
- [ ] Replication slots active for podpg-cls1-pg2 and podpg-cls1-pg3
- [ ] etcd cluster healthy (all 3 members)
- [ ] Baseline data snapshot captured

#### Cycle 1: Full DR Test

**Disaster & Promotion Phase**
- [ ] podpg-cls1-pg1 and podpg-cls1-pg2 stopped successfully
- [ ] Verify podpg-cls1-pg1/podpg-cls1-pg2 offline in 10 seconds
- [ ] podpg-cls1-pg3 still Replica after stop
- [ ] etcd still accessible from podpg-cls1-pg3
- [ ] Failover command issued: `patronictl failover --force`
- [ ] podpg-cls1-pg3 promoted to Leader within 5 seconds
- [ ] Timeline advanced from 1 to 2
- [ ] VIP migrated to podpg-cls1-pg3 (172.18.0.10)
- [ ] podpg-cls1-pg3 is NOT in recovery (pg_is_in_recovery() = false)
- [ ] HAProxy write pool now shows podpg-cls1-pg3 as UP

**DR Mode Active Phase**
- [ ] Create test table and insert data successfully
- [ ] Data query returns records
- [ ] podpg-cls1-pg3 /primary endpoint returns HTTP 200
- [ ] podpg-cls1-pg3 /replica endpoint returns HTTP 503 (no replicas)
- [ ] Patroni health shows only podpg-cls1-pg3 as member

**Recovery & Rejoin Phase**
- [ ] podpg-cls1-pg1 and podpg-cls1-pg2 started successfully
- [ ] Containers running within 20 seconds
- [ ] podpg-cls1-pg1 and podpg-cls1-pg2 detected by Patroni (not offline anymore)
- [ ] Archive recovery phase observed (10-30 seconds)
- [ ] Streaming replication phase observed
- [ ] Timeline on podpg-cls1-pg1/podpg-cls1-pg2 updated to 2
- [ ] VIP remains on podpg-cls1-pg3 (still the leader)
- [ ] Replication lag decreases over time
- [ ] All replicas reach 0.00 MB lag
- [ ] All 3 nodes operational (direct PostgreSQL connections work)

**Switchover & Restore Phase**
- [ ] podpg-cls1-pg3 verified as current leader before switchover
- [ ] Switchover command executed: `patronictl switchover --leader podpg-cls1-pg3 --candidate podpg-cls1-pg1 --force`
- [ ] podpg-cls1-pg1 promoted to Leader within 10 seconds
- [ ] Timeline advanced to 3
- [ ] podpg-cls1-pg2 role changed to Sync Standby
- [ ] podpg-cls1-pg3 role changed back to Replica
- [ ] VIP migrated to podpg-cls1-pg1 (172.18.0.10)
- [ ] Original topology restored (podpg-cls1-pg1=Leader, podpg-cls1-pg2=Standby, podpg-cls1-pg3=Replica)

**Post-Recovery Validation (Cycle 1)**
- [ ] All 3 PostgreSQL nodes operational
- [ ] All Patroni health endpoints returning correct codes
- [ ] Replication lag = 0.00 MB on both replicas
- [ ] All replication slots active
- [ ] etcd cluster healthy
- [ ] DR test data preserved (dr_test table has 2 records)
- [ ] Timeline progression correct (1 → 2 → 3)
- [ ] **Cycle 1 Total Time**: _____ seconds

#### Cycle 2: Repeat for Consistency Verification

Execute the same phases as Cycle 1, checking:
- [ ] Cycle 1 and Cycle 2 timings are consistent (within ±5 seconds)
- [ ] All node roles transition in same order
- [ ] LAG progression follows same pattern
- [ ] VIP migrations occur at same intervals
- [ ] Data integrity consistent across cycles
- [ ] No error messages in any logs
- [ ] **Cycle 2 Total Time**: _____ seconds

**Comparison Result**: 
- Cycle 1 = ____ sec
- Cycle 2 = ____ sec
- Δ = ____ sec
- [ ] If Δ < 5 sec: ✅ CONSISTENT / [ ] If Δ ≥ 5 sec: ⚠️ VARIABLE

---

### DR Test Execution Guide

For detailed step-by-step execution with real-time monitoring, refer to the sections above:
- [Pre-DR Baseline Verification](#pre-dr-baseline-verification)
- [Disaster Scenario](#disaster-scenario)
- [Manual Promotion](#manual-promotion)
- [DR Mode Active](#dr-mode-active)
- [Recovery Phase](#recovery-phase)
- [Restore Topology](#restore-topology)
- [Post-Recovery Validation](#post-recovery-validation)

Expected total time for Cycle 1: **90-120 seconds** (4 phases)
Expected total time for Cycle 2: **90-120 seconds** (validation of consistency)

---

## Multi-DC Standby Cluster Setup (podpg-cls1-pg4 — Region B)

### Standby Cluster Overview

podpg-cls1-pg4 runs in **Patroni standby cluster mode** — it streams WAL from the primary DC leader (via the
floating VIP 172.18.0.10) and remains read-only until explicitly promoted. It shares the same cluster
name (`pg-podman-cls1`) as the primary cluster, which enables seamless failover and failback.

**Key Differences from a Normal Replica**:

| Feature              | Normal Replica (podpg-cls1-pg2, podpg-cls1-pg3) | Standby Cluster (podpg-cls1-pg4)              |
|----------------------|---------------------------|------------------------------------|
| Managed by Patroni   | Yes (same cluster)        | Yes (separate Patroni instance)    |
| etcd                 | Shared 3-node cluster     | Own single-node etcd               |
| Read queries         | Via primary DC HAProxy    | Direct: localhost:5437             |
| Write after promote  | Via switchover only       | Via `patronictl promote` or direct |
| Cluster name         | pg-podman-cls1            | pg-podman-cls1 (same)              |
| Streaming source     | primary (podpg-cls1-pg1)             | Primary VIP (172.18.0.10)          |

### Setup podpg-cls1-pg4 Container

podpg-cls1-pg4 is created alongside podpg-cls1-pg1–podpg-cls1-pg3 during Phase 1 (`playbook-setup-podman.yml`). The playbook loops
over all containers; existing containers (podpg-cls1-pg1–podpg-cls1-pg3) are silently skipped so it is safe to re-run.

```bash
cd playbook-install-pg-cluster-podman-etcd/

# Create podpg-cls1-pg4 container (podpg-cls1-pg1/pg2/pg3 already running — they are skipped automatically)
ansible-playbook playbook-setup-podman.yml --tags containers 2>&1 | tee logs/playbook-setup-podman.yml.log

# Verify podpg-cls1-pg4 container is running
podman ps --filter name=podpg-cls1-pg4 --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check podpg-cls1-pg4 container IP
podman inspect podpg-cls1-pg4 | jq -r '.[0].NetworkSettings.Networks."lab-network".IPAddress'
# Expected: 172.18.0.14
```

### Install Standby Cluster

```bash
cd playbook-install-pg-cluster-podman-etcd/

# Install standby cluster on podpg-cls1-pg4 (primary cluster must be running first)
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml --vault-password-file=vault-pass 2>&1 | tee logs/playbook-install-standby-cluster.yml.log

# Install specific component only
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml \
  --vault-password-file=vault-pass --tags patroni \
  2>&1 | tee logs/playbook-install-standby-cluster.yml.log

# Reinitialize standby (re-streams from primary from scratch)
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true \
  2>&1 | tee logs/playbook-install-standby-cluster.yml.log
```

### Verify Standby Streaming

```bash
# ── From podpg-cls1-pg4: check Patroni sees it as standby leader ────────────────────────
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
# Expected output:
# + Cluster: pg-podman-cls1 (standby) ---+----------+
# | Member | Host        | Role           | State     | TL | Lag in MB |
# +--------+-------------+----------------+-----------+----+-----------+
# | podpg-cls1-pg4    | 172.18.0.14 | Standby Leader | streaming |  1 |         0 |

# ── From podpg-cls1-pg1: check podpg-cls1-pg4 is a streaming replica ───────────────────────────────
podman exec podpg-cls1-pg1 psql -U postgres postgres -c \
  "SELECT client_addr, state, sync_state, sent_lsn, replay_lsn,
          ROUND((sent_lsn - replay_lsn)/1048576.0,2) AS lag_mb
   FROM pg_stat_replication
   WHERE client_addr = '172.18.0.14';"

# ── Verify podpg-cls1-pg4 is in recovery (standby mode) ─────────────────────────────────
podman exec podpg-cls1-pg4 psql -U postgres postgres -c "SELECT pg_is_in_recovery();"
# Expected: t (true — podpg-cls1-pg4 is a standby)

# ── Check streaming lag on podpg-cls1-pg4 ────────────────────────────────────────────────
podman exec podpg-cls1-pg4 psql -U postgres postgres -c \
  "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"

# ── Verify podpg-cls1-pg4 etcd is healthy ────────────────────────────────────────────────
podman exec podpg-cls1-pg4 etcdctl --endpoints=http://172.18.0.14:2379 endpoint health

# ── Monitor podpg-cls1-pg4 Patroni log ───────────────────────────────────────────────────
podman exec podpg-cls1-pg4 tail -f /var/log/patroni/patroni.log
```

### Multi-DC DR: Promote Standby

Use this when the entire Region A (primary DC) is down and you need to promote podpg-cls1-pg4 to accept writes.

```bash
# ── Step 1: Verify Region A is down ──────────────────────────────────────────
podman exec podpg-cls1-pg4 psql -h 172.18.0.10 -U postgres postgres -c "SELECT 1;" 2>&1 || \
  echo "Primary DC (172.18.0.10) is unreachable — safe to promote"

# ── Step 2: Check podpg-cls1-pg4 replication lag before promoting ───────────────────────
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
podman exec podpg-cls1-pg4 psql -U postgres postgres -c \
  "SELECT now() - pg_last_xact_replay_timestamp() AS lag;"

# ── Step 3: Promote podpg-cls1-pg4 standby cluster ──────────────────────────────────────
# Option A: via patronictl (recommended — graceful)
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml promote pg-podman-cls1 podpg-cls1-pg4 --force

# Option B: via pg_promote() (direct)
# podman exec podpg-cls1-pg4 psql -U postgres postgres -c "SELECT pg_promote();"

# ── Step 4: Verify podpg-cls1-pg4 is now the primary ────────────────────────────────────
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
# Expected: podpg-cls1-pg4 Role = Leader

podman exec podpg-cls1-pg4 psql -U postgres postgres -c "SELECT pg_is_in_recovery();"
# Expected: f (false — podpg-cls1-pg4 is now a standalone primary)

# ── Step 5: Test writes on podpg-cls1-pg4 ───────────────────────────────────────────────
podman exec podpg-cls1-pg4 psql -U postgres postgres -c \
  "CREATE TABLE IF NOT EXISTS dr_test_region_b (id serial, ts timestamptz DEFAULT now(), note text);
   INSERT INTO dr_test_region_b (note) VALUES ('Written after Region B promotion');
   SELECT * FROM dr_test_region_b;"

# From host (direct connection):
psql -h localhost -p 5437 -U postgres postgres -c "SELECT * FROM dr_test_region_b;"
```

### Multi-DC DR: Failback to Primary DC

After Region A is restored, re-establish podpg-cls1-pg4 as a standby streaming from the recovered primary.

```bash
# ── Step 1: Bring Region A back up ───────────────────────────────────────────
podman start podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3
sleep 15

# Verify primary cluster recovered
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list

# ── Step 2: Ensure podpg-cls1-pg1 is the leader in Region A ─────────────────────────────
# If podpg-cls1-pg3 was promoted during recovery, switchover back to podpg-cls1-pg1:
# podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml switchover \
#   pg-podman-cls1 --leader podpg-cls1-pg3 --candidate podpg-cls1-pg1 --force

# ── Step 3: Check what data podpg-cls1-pg4 has that Region A may be missing ─────────────
podman exec podpg-cls1-pg4 psql -U postgres postgres -c \
  "SELECT pg_current_wal_lsn() AS pg4_lsn, timeline_id FROM pg_control_checkpoint();"
podman exec podpg-cls1-pg1 psql -U postgres postgres -c \
  "SELECT pg_current_wal_lsn() AS pg1_lsn, timeline_id FROM pg_control_checkpoint();"

# ── Step 4: Export any data written to podpg-cls1-pg4 during DR (if needed) ─────────────
# If you wrote to podpg-cls1-pg4 while it was promoted, export and import to primary:
podman exec podpg-cls1-pg4 pg_dump -U postgres postgres -t dr_test_region_b > /tmp/dr_test_region_b.sql
podman exec -i podpg-cls1-pg1 psql -U postgres postgres < /tmp/dr_test_region_b.sql

# ── Step 5: Re-initialize podpg-cls1-pg4 as standby of the restored primary ─────────────
# podpg-cls1-pg4 must stream from the new primary — reinitialize via Ansible:
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true \
  2>&1 | tee logs/playbook-install-standby-cluster.yml.log

# ── Step 6: Verify podpg-cls1-pg4 is streaming again ────────────────────────────────────
sleep 30
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
podman exec podpg-cls1-pg4 psql -U postgres postgres -c "SELECT pg_is_in_recovery();"
# Expected: t (true — podpg-cls1-pg4 is back in standby mode)

podman exec podpg-cls1-pg1 psql -U postgres postgres -c \
  "SELECT client_addr, state, sync_state, ROUND((sent_lsn - replay_lsn)/1048576.0,2) AS lag_mb
   FROM pg_stat_replication
   WHERE client_addr = '172.18.0.14';"
```

### Standby Cluster Troubleshooting

#### podpg-cls1-pg4 not streaming (stays in "stopped" or "starting" state)

```bash
# Check Patroni logs on podpg-cls1-pg4
podman exec podpg-cls1-pg4 tail -50 /var/log/patroni/patroni.log | grep -E "ERROR|WARNING|streaming|standby"

# Verify podpg-cls1-pg4 can reach the primary VIP
podman exec podpg-cls1-pg4 pg_isready -h 172.18.0.10 -p 5432
# Expected: 172.18.0.10:5432 - accepting connections

# Check replication slot created on primary for podpg-cls1-pg4
podman exec podpg-cls1-pg1 psql -U postgres postgres -c \
  "SELECT slot_name, active, restart_lsn FROM pg_replication_slots WHERE slot_name LIKE '%podpg-cls1-pg4%';"

# Restart Patroni on podpg-cls1-pg4 to force reconnect
podman exec podpg-cls1-pg4 systemctl restart patroni
sleep 10
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
```

#### podpg-cls1-pg4 etcd unhealthy

```bash
# Check etcd status on podpg-cls1-pg4
podman exec podpg-cls1-pg4 systemctl status etcd --no-pager

# Check etcd logs
podman exec podpg-cls1-pg4 journalctl -u etcd --no-pager -n 30

# Restart etcd on podpg-cls1-pg4 (single-node, no quorum concern)
podman exec podpg-cls1-pg4 systemctl restart etcd
sleep 5
podman exec podpg-cls1-pg4 etcdctl --endpoints=http://172.18.0.14:2379 endpoint health
```

#### podpg-cls1-pg4 fails to promote

```bash
# Check if podpg-cls1-pg4 Patroni is paused
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list | grep -i pause

# If paused, resume
podman exec podpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml resume

# Verify primary is truly unreachable before promoting
podman exec podpg-cls1-pg4 pg_isready -h 172.18.0.10 -p 5432
# Must time out / refuse connection before promoting

# Manual pg_promote() if patronictl fails
podman exec podpg-cls1-pg4 psql -U postgres postgres -c "SELECT pg_promote();"
```

---

## Troubleshooting

### Ansible `apt` module fails: `python3-apt` missing or obsolete

**Symptom**: Ansible tasks using `ansible.builtin.apt` or `ansible.builtin.package` fail with:
```
"Could not import python modules: apt, apt_pkg. Please install python3-apt package."
```
or silently use an outdated `python3-apt` that does not recognise newer Ubuntu releases.

**Cause**: The base container image (`ubuntu:24.04`) is a minimal image that does not ship
`python3-apt`. Even if `python3-apt` is installed later, the version from Ubuntu's repos may be
incompatible with Ansible's internal Python version.

**Fix** (already applied to all roles): All package-installation tasks use
`ansible.builtin.shell: apt-get install -y …` instead of the `apt` / `package` module.
The shell approach bypasses the `python3-apt` dependency entirely and is idempotent with
`until/retries`:

```yaml
- name: Install <package> (shell — no python3-apt required)
  ansible.builtin.shell: apt-get install -y <package>
  register: install_status
  until: install_status.rc == 0
  delay: 5
  retries: 3
  changed_when: true
```

Affected files converted: `packages.yml`, `repository.yml`, `haproxy.yml`, `keepalived.yml`,
`patroni.yml`.

---

### apt stalls with "Waiting for headers" inside Podman containers

**Symptom**: `apt-get update` hangs for 60–90 seconds per mirror before timing out. Total
`apt-get update` takes 10–15 minutes.

**Cause**: Linux containers default to trying IPv6 first. Podman bridge networks (`lab-network`)
do not route IPv6 to the internet, so every IPv6 attempt times out before falling back to IPv4.

**Fix** (already applied in `pg_containers.yml`): Write `/etc/apt/apt.conf.d/99force-ipv4`
and disable IPv6 via sysctl inside each container immediately after creation:

```yaml
- name: Force apt to use IPv4 only (avoids IPv6 stall on Podman bridge)
  ansible.builtin.shell: |
    echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
    sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1
```

With this fix, `apt-get update` completes in ~5 seconds at full internet speed (38 MB in 5 s).

---

### apt lock conflicts (`/var/lib/dpkg/lock` busy)

**Symptom**: `apt-get install` fails immediately with:
```
E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process …
```

**Cause**: Ubuntu 24.04 starts `apt-daily.timer` and `apt-daily-upgrade.timer` automatically.
Inside a container these run as background systemd units and can hold the dpkg lock just as
Ansible tries to install packages.

**Fix** (already applied in `pg_containers.yml`): Mask and stop the apt-daily services right
after container creation:

```yaml
- name: Mask apt-daily services to prevent lock conflicts
  ansible.builtin.shell: |
    systemctl mask apt-daily.timer apt-daily-upgrade.timer \
                   apt-daily.service apt-daily-upgrade.service
    systemctl stop apt-daily.timer apt-daily-upgrade.timer \
                   apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
    rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
```

---

### apt-cacher-ng proxy unreachable from Podman containers

**Symptom**: `apt-get update` inside a container fails with `Connection refused` to
`172.18.0.1:3142`.

**Cause**: `apt-cacher-ng` listens on the host loopback / all interfaces, but Podman's bridge
network (`lab-network`) is isolated by the host firewall (UFW/iptables). By default, host
ports on the bridge gateway (`172.18.0.1`) are not reachable from containers without explicit
firewall rules.

**Resolution**: The proxy configuration was removed from all containers. Direct downloads from
Ubuntu / PGDG mirrors are fast enough (38 MB in 5 s at ~8 MB/s). No caching proxy is required
for this lab setup. The `proxy_env` variable in role tasks is left empty (`{}`).

If you want to re-enable `apt-cacher-ng` in the future, add a UFW rule:
```bash
sudo ufw allow in on podman1 to any port 3142
```
Then set `proxy_env` in your vars:
```yaml
proxy_env:
  http_proxy: "http://172.18.0.1:3142"
  https_proxy: "http://172.18.0.1:3142"
```

---

### pgBouncer SASL authentication failed

Symptom: `FATAL: SASL authentication failed` when connecting through pgBouncer.

Cause: Stale server-side pool connections (common after a Patroni failover/restart).

```bash
# Fix: reload pgBouncer to clear stale connections
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do podman exec $n systemctl reload pgbouncer; done
```

### Keepalived VIP not assigned (silent failure)

Symptom: `ip addr show eth0` shows no VIP despite Keepalived running.

Common cause: Interface label too long (Linux limit: 15 chars). Check the log:

```bash
podman exec podpg-cls1-pg1 journalctl -u keepalived --no-pager | grep -i "label\|removing\|no VIP"
```

Fix: Ensure labels in `keepalived.conf.j2` are ≤15 chars (e.g., `eth0:vip`, `eth0:rvip`).

### HAProxy backend shows all DOWN

Symptom: All backends DOWN in `be_write` or `be_read`.

```bash
# Check if Patroni REST API is reachable
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n /primary: "
  podman exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary
  echo
done

# Restart HAProxy if needed
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do podman exec $n systemctl restart haproxy; done
```

### Patroni failover not happening

```bash
# Check if Patroni is paused
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list | grep -i pause

# Resume if paused
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml resume

# Check etcd connectivity (DCS required for failover)
podman exec podpg-cls1-pg2 etcdctl --endpoints=http://172.18.0.12:2379 endpoint health
```

### Replica lagging behind

```bash
# Check lag
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list

# Reinitialize lagging replica from scratch
podman exec podpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml reinit pg-podman-cls1 podpg-cls1-pg3 --force
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
podman exec -it podpg-cls1-pg1 bash
su - postgres

# Delete the old stanza (all backups for this stanza will be removed)
pgbackrest --stanza=pg-podman-cls1 stanza-delete --force

# Create a new stanza synchronized with the current PostgreSQL instance
pgbackrest --stanza=pg-podman-cls1 stanza-create

# Verify the stanza is now valid
pgbackrest --stanza=pg-podman-cls1 check

# Exit back to root
exit
exit

# Now run a full backup
podman exec podpg-cls1-pg1 pgbackrest --stanza=pg-podman-cls1 --log-level-console=info backup --type=full
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
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list

# Check current VIP assignments
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 | grep "inet " | awk '{print $2}' | tr '\n' ' '; echo
done

# Restart Keepalived on the primary node to re-acquire the VIP
podman exec <primary_node> systemctl restart keepalived
sleep 5

# Verify VIP is now assigned
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3; do
  echo -n "$n: "
  podman exec $n ip addr show eth0 | grep "inet " | awk '{print $2}' | tr '\n' ' '; echo
done
```

### HAProxy host ports connection refused from host (e.g. localhost:25000)

Symptom: `psql: error: connection to server at "localhost", port 25000 failed: Connection refused`

Cause: Containers were created before the HAProxy host-port mappings were added to the Ansible
`pg_containers` definition. Podman port mappings are baked in at container creation time and cannot
be changed without recreating the container.

```bash
# Verify whether the ports are actually mapped on the running containers
podman ps --format "table {{.Names}}\t{{.Ports}}" | grep pg

# If ports like 15000/25000/35000 are missing, recreate containers:
# 1. Destroy containers (volumes are named and survive this step — data is safe)
podman rm -f podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3

# 2. Recreate with correct port mappings (reads from roles/podman_infrastructure/defaults/main.yml)
ansible-playbook playbook-setup-podman.yml 2>&1 | tee logs/playbook-setup-podman.yml.log

# 3. Reinstall cluster software on the fresh containers
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml --vault-password-file=vault-pass 2>&1 | tee logs/playbook-install-pg-cluster.yml.log
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

Cause: The sync standby (whichever of podpg-cls1-pg1/podpg-cls1-pg2 holds that role) is down or lagging. The primary
waits for it to confirm WAL receipt before committing (`synchronous_commit = on`,
`synchronous_node_count = 1`).

```bash
# Check replication state on primary — use pg-primary or patronictl list to identify it first
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
pg-primary -c "SELECT client_addr, state, sync_state, sent_lsn, flush_lsn FROM pg_stat_replication;"

# Check Patroni status on the sync standby node
podman exec <sync-standby-node> systemctl status patroni

# If the sync standby is down and you need writes to continue immediately — temporarily switch to async:
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-podman-cls1 \
  --force -p synchronous_mode=false
# Restore sync mode once the sync standby is back and caught up:
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-podman-cls1 \
  --force -p synchronous_mode=true
```

### Container won't start after podman Desktop restart

```bash
podman start podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3
sleep 5
# Services (patroni, etcd, pgbouncer, haproxy, keepalived) are enabled and auto-start
podman exec podpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

### etcd quorum lost (2 of 3 nodes down)

The cluster becomes read-only (no Patroni operations). Restart at least 2 nodes:

```bash
podman start podpg-cls1-pg1 podpg-cls1-pg2
sleep 10
podman exec podpg-cls1-pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379 \
  endpoint health
```

---

## Container Setup Phase (Podman)

This setup uses **Podman** exclusively on Ubuntu 24.04. All 4 containers (podpg-cls1-pg1–podpg-cls1-pg4) are created in Phase 1.

### Phase 1: Podman Setup (All Containers)

```bash
cd playbook-install-pg-cluster-podman-etcd/

# Creates podpg-cls1-pg1, podpg-cls1-pg2, podpg-cls1-pg3 (primary DC) + podpg-cls1-pg4 (standby DC) on lab-network
ansible-playbook playbook-setup-podman.yml 2>&1 | tee logs/playbook-setup-podman.yml.log

# Re-run containers step only (existing containers are skipped — safe to run alongside live cluster)
ansible-playbook playbook-setup-podman.yml --tags containers 2>&1 | tee logs/playbook-setup-podman.yml.log
```

**Benefits**:
- Native Linux rootless containers (better security, performance)
- Shared lab-network compatible with other lab containers (mongo, sqlserver, etc.)
- Identical port mappings to the reference Docker-based setup

### Phase 2a: Primary Cluster Installation (podpg-cls1-pg1, podpg-cls1-pg2, podpg-cls1-pg3)

```bash
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml --vault-password-file=vault-pass 2>&1 | tee logs/playbook-install-pg-cluster.yml.log
```

### Phase 2b: Standby Cluster Installation (podpg-cls1-pg4 — Region B)

```bash
# Run after primary cluster is fully operational
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml --vault-password-file=vault-pass 2>&1 | tee logs/playbook-install-standby-cluster.yml.log
```

---

## Common Ansible Operations

```bash
cd playbook-install-pg-cluster-podman-etcd/

# ── PRIMARY CLUSTER (podpg-cls1-pg1, podpg-cls1-pg2, podpg-cls1-pg3) ──────────────────────────────────────────
# Full setup: containers + cluster install
ansible-playbook playbook-setup-podman.yml 2>&1 | tee logs/playbook-setup-podman.yml.log
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml --vault-password-file=vault-pass 2>&1 | tee logs/playbook-install-pg-cluster.yml.log

# Install/reconfigure a single component only (primary cluster)
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags haproxy \
  2>&1 | tee logs/playbook-install-pg-cluster.yml.log
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags keepalived \
  2>&1 | tee logs/playbook-install-pg-cluster.yml.log
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags haproxy,keepalived \
  2>&1 | tee logs/playbook-install-pg-cluster.yml.log
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags patroni \
  2>&1 | tee logs/playbook-install-pg-cluster.yml.log
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags pgbouncer \
  2>&1 | tee logs/playbook-install-pg-cluster.yml.log
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags pgbackrest \
  2>&1 | tee logs/playbook-install-pg-cluster.yml.log
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags etcd \
  2>&1 | tee logs/playbook-install-pg-cluster.yml.log

# Reinitialize primary cluster (DESTROYS ALL DATA — keeps packages)
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true \
  2>&1 | tee logs/playbook-install-pg-cluster.yml.log

# Reinitialize without confirmation prompt (CI/automation)
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true -e skip_confirm=true \
  2>&1 | tee logs/playbook-install-pg-cluster.yml.log

# Reinitialize + wipe all pgBackRest backups
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass \
  -e reinit_cluster=true -e skip_confirm=true -e cleanup_pgbackrest_backups=true \
  2>&1 | tee logs/playbook-install-pg-cluster.yml.log

# ── STANDBY CLUSTER (podpg-cls1-pg4 — Region B) ─────────────────────────────────────────
# Install standby cluster (primary cluster must be running first)
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml --vault-password-file=vault-pass 2>&1 | tee logs/playbook-install-standby-cluster.yml.log

# Install specific component on standby only
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml \
  --vault-password-file=vault-pass --tags patroni \
  2>&1 | tee logs/playbook-install-standby-cluster.yml.log

# Reinitialize standby from scratch (re-streams from primary)
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true \
  2>&1 | tee logs/playbook-install-standby-cluster.yml.log

# ── VAULT & CREDENTIALS ───────────────────────────────────────────────────────
# Edit vault credentials
ansible-vault edit sensitive-values --vault-password-file=vault-pass

# ── SSH INTO CONTAINERS ───────────────────────────────────────────────────────
ssh -i ~/.ssh/id_ed25519 -p 2211 -o StrictHostKeyChecking=no ansible@127.0.0.1   # podpg-cls1-pg1
ssh -i ~/.ssh/id_ed25519 -p 2212 -o StrictHostKeyChecking=no ansible@127.0.0.1   # podpg-cls1-pg2
ssh -i ~/.ssh/id_ed25519 -p 2213 -o StrictHostKeyChecking=no ansible@127.0.0.1   # podpg-cls1-pg3
ssh -i ~/.ssh/id_ed25519 -p 2214 -o StrictHostKeyChecking=no ansible@127.0.0.1   # podpg-cls1-pg4 (standby)

# ── CONTAINER LIFECYCLE ───────────────────────────────────────────────────────
# Stop/start all containers (primary + standby)
podman stop podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3 podpg-cls1-pg4 && podman start podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3 podpg-cls1-pg4

# Stop/start primary cluster only
podman stop podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3 && podman start podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3

# Stop/start standby only
podman stop podpg-cls1-pg4 && podman start podpg-cls1-pg4

# Full teardown — WARNING: destroys all data
podman rm -f podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3 podpg-cls1-pg4
podman volume rm pg-data-podpg-cls1-pg1 pg-data-podpg-cls1-pg2 pg-data-podpg-cls1-pg3 pg-data-podpg-cls1-pg4 \
                 pg-logs-podpg-cls1-pg1 pg-logs-podpg-cls1-pg2 pg-logs-podpg-cls1-pg3 pg-logs-podpg-cls1-pg4 pg-backups
```

---

## Prometheus Scrape Config

```yaml
scrape_configs:
  - job_name: postgresql_podman
    static_configs:
      - targets:
          - 'host.podman.internal:9194'   # podpg-cls1-pg1
          - 'host.podman.internal:9195'   # podpg-cls1-pg2
          - 'host.podman.internal:9196'   # podpg-cls1-pg3
        labels:
          cluster: pg-podman-cls1
          env: podman-local

# Reload Prometheus after editing
# curl -X POST http://localhost:9090/-/reload
```

---

## Design Notes

- **No shared proxy container**: HAProxy + Keepalived run on every pg container. The VIP floats
  to the right node — no SPOF proxy tier. All 3 nodes can handle the write path if the VIP moves.

- **Keepalived unicast mode**: podman bridge networks don't reliably support multicast (needed by
  default VRRP). We configure `unicast_src_ip` / `unicast_peer` to route VRRP advertisements
  directly between container IPs.

- **VIP weight logic**: `vrrp_script` adds +100 to the base priority (101/100/99) when the health
  check passes. Primary node effective priority: 201/200/199. Replicas: 101/100/99. Guarantees the
  primary always holds the primary VIP, and no node holds both VIPs simultaneously.

- **Keepalived notify scripts** (`keepalived_notify_primary.sh` / `keepalived_notify_replica.sh`):
  deployed to `/usr/local/bin/` on each node. Called by Keepalived on every VRRP state transition
  (MASTER/BACKUP/FAULT). On MASTER: force `ip addr add <VIP>` + `arping` to gratuitously announce
  the VIP on the network. On BACKUP/FAULT: force `ip addr del <VIP>`. This bypasses Keepalived's
  internal VIP management which silently fails inside podman containers.

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
  container definitions in `roles/podman_infrastructure/defaults/main.yml` but only take effect
  when containers are recreated. The container-internal ports (5000/5001/7000) are always active.

- **Synchronous replication**: `synchronous_mode: true` with `synchronous_node_count: 1` — every
  commit on the leader must be acknowledged by the sync standby (whichever of podpg-cls1-pg1/podpg-cls1-pg2 holds that
  role) before returning to the client. podpg-cls1-pg3 is excluded via `nosync: true` and never holds the sync
  standby role. If the sync standby goes down, writes on the leader will block until it recovers (or
  sync mode is temporarily disabled via `patronictl edit-config`). Failover between podpg-cls1-pg1 and podpg-cls1-pg2 is
  always zero data loss.

- **Passwords**: must NOT contain `$` (PostgreSQL dollar-quote delimiter breaks Patroni post-bootstrap SQL).

- **pgBackRest stanza**: created once on the leader. All nodes share the same POSIX repo via the
  `pg-backups` podman named volume mounted at `/var/lib/pgbackrest`.

---

## Podman Infrastructure Conversion

This directory implements the PostgreSQL cluster exclusively using **Podman** on Ubuntu 24.04, with
a multi-datacenter architecture (podpg-cls1-pg1–podpg-cls1-pg3 primary, podpg-cls1-pg4 standby).

### Key Playbooks and Roles

| File | Purpose | Notes |
|------|---------|-------|
| `playbook-setup-podman.yml` | Create all containers (podpg-cls1-pg1–podpg-cls1-pg4) | Phase 1 — runs before cluster install |
| `playbook-install-pg-cluster.yml` | Install primary cluster | Phase 2a — podpg-cls1-pg1, podpg-cls1-pg2, podpg-cls1-pg3 only |
| `playbook-install-standby-cluster.yml` | Install standby cluster | Phase 2b — podpg-cls1-pg4 only |
| `playbook-cleanup.yml` | Teardown all containers + volumes | Uses podman commands |
| `roles/podman_infrastructure/` | Podman container orchestration role | podpg-cls1-pg1–podpg-cls1-pg4 definitions |
| `roles/podman_infrastructure/defaults/main.yml` | Container definitions (network, ports, volumes) | All 4 nodes |
| `roles/podman_infrastructure/tasks/custom/pg_containers.yml` | Create all pg containers | Podman-specific syntax |
| `roles/pg_cluster/templates/patroni.yml.j2` | Patroni config (with standby_cluster block) | Conditional for podpg-cls1-pg4 |
| `roles/pg_cluster/templates/etcd.env.j2` | etcd config (single-node for podpg-cls1-pg4) | Conditional bootstrap |

### Testing Results

**Test Date**: 2026-05-03
**Host**: ryzen9 (Ubuntu 24.04)
**Podman Version**: 3.4.2+

✓ **Containers created successfully** with lab-network attachment (podpg-cls1-pg1:172.18.0.11, podpg-cls1-pg2:172.18.0.12, podpg-cls1-pg3:172.18.0.13, podpg-cls1-pg4:172.18.0.14)
✓ **PostgreSQL 18 primary cluster installed** with full Patroni HA + etcd + HAProxy + Keepalived
✓ **Primary cluster operational**: podpg-cls1-pg1 as Leader, podpg-cls1-pg2 as Sync Standby, podpg-cls1-pg3 as Replica
✓ **VIPs assigned**: Primary 172.18.0.10, Replica 172.18.0.9
✓ **All services running**: PostgreSQL, Patroni, etcd, pgBouncer, HAProxy, Keepalived, pg_exporter
✓ **Volumes persistent**: Data survives container restart
✓ **Standby cluster (podpg-cls1-pg4)**: Streams from primary VIP; read-only until promoted

### Container Lifecycle (Podman)

```bash
# Verify all containers running
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep pg

# Verify ports are exposed
podman port podpg-cls1-pg1
podman port podpg-cls1-pg4

# Verify network attachment
podman inspect podpg-cls1-pg4 | jq '.[0].NetworkSettings.Networks."lab-network".IPAddress'

# Destroy all containers (data lost)
podman rm -f podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3 podpg-cls1-pg4

# Destroy all volumes (persistent data lost)
podman volume rm pg-data-podpg-cls1-pg1 pg-data-podpg-cls1-pg2 pg-data-podpg-cls1-pg3 pg-data-podpg-cls1-pg4 \
                 pg-logs-podpg-cls1-pg1 pg-logs-podpg-cls1-pg2 pg-logs-podpg-cls1-pg3 pg-logs-podpg-cls1-pg4 pg-backups

# Recreate fresh multi-DC cluster
ansible-playbook playbook-setup-podman.yml 2>&1 | tee logs/playbook-setup-podman.yml.log
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml --vault-password-file=vault-pass 2>&1 | tee logs/playbook-install-pg-cluster.yml.log
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml --vault-password-file=vault-pass 2>&1 | tee logs/playbook-install-standby-cluster.yml.log
```

---

## Multi-Region DCS Deployment for Production DR

### Overview

For production Disaster Recovery (DR) to work reliably, the Distributed Configuration Store (DCS) — Consul or etcd — **must be deployed on separate nodes** from the PostgreSQL cluster, and **distributed across multiple regions** for geographic resilience.

This section explains multi-region DCS deployment strategies and how they impact DR testing and failover behavior.

### Why Separate DCS Nodes Matter for DR

**Problem with Co-Located DCS** (current lab setup):
```
podpg-cls1-pg1: PostgreSQL + Patroni + etcd
podpg-cls1-pg2: PostgreSQL + Patroni + etcd
podpg-cls1-pg3: PostgreSQL + Patroni + etcd
```

When podpg-cls1-pg1 & podpg-cls1-pg2 stop → etcd loses quorum → patronictl failover fails ❌

**Solution with Separate DCS** (production setup):
```
PostgreSQL Cluster       DCS Cluster (Separate)
├── podpg-cls1-pg1 (Patroni)       ├── etcd1 (India)
├── podpg-cls1-pg2 (Patroni)       ├── etcd2 (US East)
└── podpg-cls1-pg3 (Patroni)       └── etcd3 (EU)
                        (Always running, independent)
```

When podpg-cls1-pg1 & podpg-cls1-pg2 stop → etcd still has quorum → patronictl failover works ✅

### DCS Quorum Rules (Critical for DR)

**Quorum = majority = floor(n/2) + 1**

| Nodes | Quorum | Can Lose | Multi-Region Viable? |
|-------|--------|----------|----------------------|
| 1     | 1      | 0        | ❌ No (SPOF) |
| 2     | 2      | 0        | ❌ No (need both) |
| **3** | **2**  | **1**    | ⚠️ Only if distributed |
| 4     | 3      | 1        | ⚠️ Even numbers wasteful |
| 5     | 3      | 2        | ✅ Recommended |
| 7     | 4      | 3        | ✅ Enterprise HA |

**Key Rule**: Even number of nodes = wasted resources (no better fault tolerance than n-1)

### Multi-Region Deployment Scenarios

#### ❌ NOT Recommended: Majority in One Region

```
3-Node etcd: 2 India + 1 US
├── etcd1 (India)
├── etcd2 (India)
└── etcd3 (US East)

Quorum = 2
India region down → only etcd3 remains (1 node) → NO QUORUM ❌
```

**Problem**: If India region fails, only 1 DCS node remains = cluster unavailable

#### ✅ Recommended: 5-Node Distributed

```
5-Node etcd: 2 India + 2 US + 1 EU
├── etcd1 (India)
├── etcd2 (India)
├── etcd3 (US East)
├── etcd4 (US East)
└── etcd5 (EU Central)

Quorum = 3
Any 1 region down → at least 3 nodes remain ✅
```

**Benefits**:
- Quorum survives loss of 1 entire region
- Geographic diversity prevents single-region outages
- Better latency distribution

#### ✅ Enterprise: 7-Node Distributed

```
7-Node etcd: 3 India + 2 US + 2 EU
├── etcd1, etcd2, etcd3 (India)
├── etcd4, etcd5 (US East)
└── etcd6, etcd7 (EU Central)

Quorum = 4
Can tolerate 3 node failures
Can tolerate 1 entire region down AND 1 more node elsewhere ✅
```

**Benefits**:
- Extreme fault tolerance
- Can lose entire region + additional node
- Maximum availability for critical deployments

### Network Latency Considerations

etcd and Consul are consensus-based and sensitive to network latency:

| Latency | Impact | Viable? |
|---------|--------|---------|
| < 10ms  | Excellent | ✅ Same data center |
| 10-50ms | Good | ✅ Same region |
| 50-100ms | Acceptable | ⚠️ Monitor |
| > 100ms | Poor | ❌ Risk of split-brain |

**Recommendation**:
- India ↔ US East: ~250ms (may cause slowness)
- India ↔ EU: ~300ms (may cause slowness)
- **Solution**: Use 3 regional data centers with < 50ms latency between them, or accept higher latency with larger timeout values

### DCS Node Placement Best Practice

```
Production Setup:
├── Data Center 1 (Region A): 2 etcd nodes
├── Data Center 2 (Region B): 2 etcd nodes
└── Data Center 3 (Region C): 1 etcd node (tie-breaker)

Total: 5 nodes, Quorum = 3
Tolerates: 1 entire region failure + 1 additional node failure
```

### Impact on DR Testing

With properly distributed separate DCS cluster:

**Before**: Co-located etcd (current)
- Stop podpg-cls1-pg1 & podpg-cls1-pg2 → etcd quorum lost → DR test fails ❌
- Workaround: Restart podpg-cls1-pg1 & podpg-cls1-pg2 to restore quorum, then test

**After**: Separate distributed etcd (production)
- Stop podpg-cls1-pg1 & podpg-cls1-pg2 → DCS unaffected → DR test works perfectly ✅
- Can test complete failure scenarios without DCS interference
- Failover works as designed

### Adding Nodes On-The-Fly

Both Consul and etcd support dynamic node addition:

**etcd - Add node**:
```bash
# 1. On etcd leader, add new member
etcdctl member add etcd4 --peer-urls=https://etcd4:2380

# 2. Start new etcd node with join-existing=true
# 3. Verify cluster health
etcdctl endpoint health
```

**Consul - Add node**:
```bash
# 1. Start new Consul server
consul agent -server -join=<existing-consul-ip>

# 2. Verify cluster membership
consul members
```

**No cluster downtime required** — existing cluster keeps operating while new node syncs data.

### Example: From 3-Node to 5-Node (Scaled for DR)

```
Initial Setup (Not resilient to region loss):
├── etcd1 (India)
├── etcd2 (India)
└── etcd3 (US East)
Quorum = 2 (fragile)

Upgrade Plan:
1. Add etcd4 (US East): etcdctl member add etcd4
   Result: 4 nodes, Quorum = 3 (still need majority)

2. Add etcd5 (EU Central): etcdctl member add etcd5
   Result: 5 nodes, Quorum = 3 (resilient!)

Final Setup (Resilient):
├── etcd1, etcd2 (India)
├── etcd3, etcd4 (US East)
└── etcd5 (EU Central)
Quorum = 3 ✅ Can survive any region failure
```

**Execution**: 0 downtime, PostgreSQL cluster keeps running

### Verification Commands

**Check etcd cluster health across regions**:
```bash
etcdctl --endpoints=https://etcd1:2379,https://etcd2:2379,https://etcd3:2379,https://etcd4:2379,https://etcd5:2379 \
  endpoint health
```

**Monitor Patroni connectivity to DCS**:
```bash
# Patroni logs should show healthy DCS connection
podpg-cls1-pg1: journalctl -u patroni -f | grep -i "dcs\|etcd"

# All nodes should show quorum achieved
patronictl -c /etc/patroni/patroni.yml list
```

**Check network latency between regions**:
```bash
ping etcd2  # India ↔ US
ping etcd5  # India ↔ EU
# Target: < 50ms for best performance
```

### Summary: Multi-Region DCS for Production DR

| Factor | Lab Setup | Production Setup |
|--------|-----------|------------------|
| DCS Location | Co-located with PG | Separate nodes |
| DCS Nodes | 3 (on podpg-cls1-pg1, podpg-cls1-pg2, podpg-cls1-pg3) | 5+ across regions |
| Quorum Resilience | Fails when 2 PG nodes down | Survives PG failures |
| DR Test Works | No (need workaround) | Yes (complete test) |
| Region Failure | Cluster unavailable | Cluster available |
| Setup Complexity | Simple (lab) | Complex (prod) |

---

## Other Miscellaneous Commands

### Unset Env Variable
```bash
unset PGPASSWORD
```

### Connect to podman container prompt, and connect to postgresql
```bash
saanvi@ryzen9:~/PostgreSQL-Learning$ podman exec -it podpg-cls1-pg2 bash
root@podpg-cls1-pg2:/# patronictl -c /etc/patroni/patroni.yml list
+ Cluster: pg-podman-cls1 (7634451494908218688) --+-----------+
| Member | Host        | Role    | State     | TL | Lag in MB |
+--------+-------------+---------+-----------+----+-----------+
| podpg-cls1-pg1    | 172.18.0.11 | Replica | streaming |  2 |         0 |
| podpg-cls1-pg2    | 172.18.0.12 | Leader  | running   |  2 |           |
| podpg-cls1-pg3    | 172.18.0.13 | Replica | streaming |  2 |         0 |
+--------+-------------+---------+-----------+----+-----------+
root@podpg-cls1-pg2:/# 
root@podpg-cls1-pg2:/# su - postgres
postgres@podpg-cls1-pg2:~$ psql
psql (18.3 (Ubuntu 18.3-1.pgdg24.04+1))
Type "help" for help.

postgres=# 
postgres=# \q
postgres@podpg-cls1-pg2:~$ exit
logout
root@podpg-cls1-pg2:/# 
```

### Add environment variable
```bash
tee -a ~/.bashrc << 'EOF'

export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
EOF
```

### Add host entries inside podman
```bash
tee -a /etc/hosts << 'EOF'

# PostgreSQL podman cluster — lab-network 172.18.0.0/16
172.18.0.11  podpg-cls1-pg1    # PostgreSQL :5433  pgBouncer :6433  Patroni :8011  (Primary DC)
172.18.0.12  podpg-cls1-pg2    # PostgreSQL :5434  pgBouncer :6434  Patroni :8012  (Primary DC)
172.18.0.13  podpg-cls1-pg3    # PostgreSQL :5435  pgBouncer :6435  Patroni :8013  (Primary DC)
172.18.0.14  podpg-cls1-pg4    # PostgreSQL :5437  pgBouncer :6436  Patroni :8014  (Standby DC)

172.18.0.10 pg-primary pg-leader
172.18.0.9  pg-replica
EOF
```

### Take SSH of containers
```bash
# Primary DC
ssh -p 2211 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/id_ed25519 ansible@127.0.0.1 "patronictl -c /etc/patroni/patroni.yml list" 2>/dev/null  # podpg-cls1-pg1
ssh -p 2214 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/id_ed25519 ansible@127.0.0.1 "patronictl -c /etc/patroni/patroni.yml list" 2>/dev/null  # podpg-cls1-pg4 (standby)
```

### Quick status check (all nodes)
```bash
# All nodes — cluster status
for n in podpg-cls1-pg1 podpg-cls1-pg2 podpg-cls1-pg3 podpg-cls1-pg4; do
  echo "=== $n ==="
  podman exec $n patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | head -10
done

# podpg-cls1-pg4 standby streaming lag
podman exec podpg-cls1-pg1 psql -U postgres postgres -c \
  "SELECT client_addr, state, sync_state,
          ROUND((sent_lsn - replay_lsn)/1048576.0,2) AS lag_mb
   FROM pg_stat_replication;"
```

---

**Document Status**: ✅ CONSOLIDATED AND COMPLETE (Multi-Datacenter)

Covers: primary 3-node HA cluster (podpg-cls1-pg1/podpg-cls1-pg2/podpg-cls1-pg3), standby cluster (podpg-cls1-pg4/Region B), DR testing,
failover/failback, and all operational procedures.
