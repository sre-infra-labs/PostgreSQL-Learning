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

### Infrastructure & Deployment
15. [Troubleshooting](#troubleshooting)
16. [Common Ansible Operations](#common-ansible-operations)
17. [Prometheus Scrape Config](#prometheus-scrape-config)
18. [Design Notes](#design-notes)
19. [Other Miscellaneous Commands](#other-miscellaneous-commands)

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
│   ├─ Region A (Primary Cluster — docpg-cls1)
│   │  ├── docpg-cls1-pg1  (172.18.0.11) — Leader or Sync Standby  (designed: Leader)
│   │  ├── docpg-cls1-pg2  (172.18.0.12) — Leader or Sync Standby  (designed: Sync Standby)
│   │  └── docpg-cls1-pg3  (172.18.0.13) — Replica                 (nosync: true — never elected Sync Standby or Leader)
│   │
│   └─ Region B (Standby Cluster — docpg-cls1) [Optional for DR]
│      └── docpg-cls1-pg4  (172.18.0.14) — Standby (single-node, streams from Region A leader)
│
└── Docker Named Volume: pg-backups  (shared pgBackRest POSIX repo)
```

### Replication Topology — Primary Cluster (Region A)

| Node              | Designed Role | Notes                                    |
|-------------------|---------------|------------------------------------------|
| docpg-cls1-pg1    | Leader        | Primary; writes committed only after docpg-cls1-pg2 acks WAL |
| docpg-cls1-pg2    | Sync Standby  | `synchronous_node_count=1`; zero data loss on pg1 failure |
| docpg-cls1-pg3    | Replica       | Async replica; `nosync: true` — never elected Sync Standby or Leader |

Roles are dynamic — Patroni may promote any node on failover. The designed topology is restored via
`patronictl switchover` after recovery.

> ⚠️ **WARNING — Synchronous Replication Costs**
>
> When using synchronous replication (like docpg-cls1-pg2 as Sync Standby):
>
> - **The cost of synchronous replication: increased latency and reduced throughput on writes.**
> - **If followers become inaccessible from the leader, the leader effectively becomes read-only.**
>
> See [Patroni Replication Modes Documentation](https://patroni.readthedocs.io/en/latest/replication_modes.html) for details.

### Multi-Region Setup (Standby Cluster — Region B)

For Disaster Recovery (DR), deploy a single-node standby cluster **docpg-cls1-pg4** in Region B that streams
from the primary cluster's leader:

```
Region A (Primary) — docpg-cls1                    Region B (Standby) — docpg-cls1
├─ docpg-cls1-pg1 (172.18.0.11) Leader             └─ docpg-cls1-pg4 (172.18.0.14) Standby
├─ docpg-cls1-pg2 (172.18.0.12) Sync Standby          (streams from pg1/pg2 via standby_cluster_slot)
└─ docpg-cls1-pg3 (172.18.0.13) Replica               (same cluster name = promotable)

All on same Docker network: lab-network (172.18.0.0/16)
```

**Key Differences from Primary:**
- docpg-cls1-pg4 is **single-node** (no local etcd consensus, minimal resources)
- docpg-cls1-pg4 is **read-only** (no writes until promoted in DR)
- docpg-cls1-pg4 streams from primary cluster leader via `standby_cluster` configuration
- **Same cluster name** (`docpg-cls1`) enables seamless promotion during DR

**When to Deploy Standby:**
- Multi-region HA/DR environment
- RPO (Recovery Point Objective) < 1 minute
- RTO (Recovery Time Objective) < 5 minutes
- Need automated/manual failover to Region B

### Ports (container-internal only — no host-port mappings)

Containers expose **zero** host ports. All services listen on their default container-internal
ports and are reached either via `docker exec <container>` from the Mac host, or directly over
the `lab-network` Docker bridge from other containers.

```
┌───────────────────┬─────────────────┬─────────────────────────────────────────────────────┐
│ Service           │ Container port  │ Notes                                               │
├───────────────────┼─────────────────┼─────────────────────────────────────────────────────┤
│ PostgreSQL        │ 5432            │ Patroni-managed                                     │
│ Patroni REST      │ 8008            │ /primary, /replica, /patroni, /cluster              │
│ pgBouncer         │ 6432            │ Connection pooler                                   │
│ pg_exporter       │ 9194            │ Prometheus scrape endpoint                          │
│ HAProxy write     │ 5000            │ /primary health → 200 only on Patroni leader        │
│ HAProxy read      │ 5001            │ /replica health → 200 on healthy replicas           │
│ HAProxy stats     │ 7000            │ HTTP UI, basic auth: admin / <PG_SUPERUSER_PWD>     │
│ etcd client/peer  │ 2379 / 2380     │ DCS — inter-container only                          │
│ SSH               │ (disabled)      │ Ansible reaches containers via docker exec          │
└───────────────────┴─────────────────┴─────────────────────────────────────────────────────┘

Per-container IPs on lab-network 172.18.0.0/16 (see hosts.yml):
  docpg-cls1-pg1: 172.18.0.11   (primary cluster)
  docpg-cls1-pg2: 172.18.0.12   (primary cluster)
  docpg-cls1-pg3: 172.18.0.13   (primary cluster, nofailover)
  docpg-cls1-pg4: 172.18.0.14   (standby cluster leader — Region B)

Keepalived VIPs (float between primary-cluster nodes):
  172.18.0.10 → current Patroni primary (write VIP)
  172.18.0.9  → current healthy replica  (read VIP)
```

### Traffic Flow

```
Application write  →  VIP 172.18.0.10:5000  →  HAProxy (any node)  →  <leader> :5432
Application read   →  VIP 172.18.0.9:5001   →  HAProxy (any node)  →  <replica> :5432

Notes:
  - Any node's HAProxy correctly routes writes to the leader and reads to replicas,
    so both VIPs work for both ports. The replica VIP (172.18.0.9) is the preferred
    read endpoint because it floats away from a node that loses its replica status.
  - All endpoints are inside the Docker lab-network. From the Mac host, reach them via
    `docker exec <container> psql ...` (see "Connecting to PostgreSQL" below).

After failover (e.g. docpg-cls1-pg2 promoted to leader after docpg-cls1-pg1 failure):
  Keepalived detects /primary passes on docpg-cls1-pg2 → primary VIP (172.18.0.10) migrates to docpg-cls1-pg2
  HAProxy health checks catch up within 6–9 s (3 × inter=3s)
  docpg-cls1-pg3 becomes a replica; restore docpg-cls1-pg1 and switchover back when ready
```

---

---

# Cluster Setup - Docker Containers + PostgreSQL 18 + Patroni + etcd + HAProxy + Keepalived

This setup uses **Docker** on macOS with a shared `lab-network` for all containers.

## Build docker image to use in the cluster

```bash
cd PostgreSQL-Learning/playbook-install-pg-cluster-docker-etcd/

# Stop and Remove Existing Containers
docker stop docpg-cls1-pg4 docpg-cls1-pg5 docpg-cls1-pg6 docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3 2>/dev/null || true

# Remove Old Containers
docker rm docpg-cls1-pg4 docpg-cls1-pg5 docpg-cls1-pg6 docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3 2>/dev/null || true

# Remove old image
docker rmi pg-cluster-node:latest

# Rebuild the Image
cd PostgreSQL-Learning/playbook-install-pg-cluster-docker-etcd/
docker build --no-cache -t pg-cluster-node:latest -f Dockerfile .

# Verify the Image Was Built
docker images | grep pg-cluster-node

# Check what image name is referenced in your container setup playbook:
grep -n "image:" playbook-setup-primary-cluster-containers.yml playbook-setup-standby-cluster-containers.yml

```

## Primary Cluster Setup

This will create patroni based `primary cluster` with `write copy`.

```bash
cd ~/Documents/Github/Personal/PostgreSQL-Learning/playbook-install-pg-cluster-docker-etcd

# docker stop docpg-cls1-pg6 docpg-cls1-pg5 docpg-cls1-pg4
# docker rm docpg-cls1-pg6 docpg-cls1-pg5 docpg-cls1-pg4
# docker start docpg-cls1-pg6 docpg-cls1-pg5 docpg-cls1-pg4

# docker stop docpg-cls1-pg3 docpg-cls1-pg2 docpg-cls1-pg1
# docker rm docpg-cls1-pg3 docpg-cls1-pg2 docpg-cls1-pg1
# docker start docpg-cls1-pg3 docpg-cls1-pg2 docpg-cls1-pg1

# Remove the old image (this forces a rebuild)
docker rmi pg-cluster-node:latest

# Cleanup containers
ansible-playbook -i hosts.yml playbook-cleanup.yml --tags containers 2>&1 | tee logs/playbook-cleanup.yml.log

# Phase 0: Validate ansible hosts
ansible-inventory -i hosts.yml --graph
ansible -i hosts.yml all --list-hosts
ansible -i hosts.yml primary_cluster --list-hosts
ansible -i hosts.yml standby_cluster --list-hosts

# Phase 1: Create Docker containers and network. Place logs in run_logs for analysis
ansible-playbook -i hosts.yml playbook-setup-primary-cluster-containers.yml 2>&1 | tee logs/playbook-setup-primary-cluster-containers.yml.log

# Phase 2: Setup Primary Patroni/PostgreSQL Cluster with one or more nodes
ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml --vault-password-file=vault-pass \
  -e reinit_cluster=true 2>&1 | tee logs/playbook-install-primary-cluster.yml.log

# Verify cluster status
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

## Standby Cluster Setup

This will create patroni based `standby cluster` that receives streaming replication from primary cluster, and can be promoted to primary if needed.

```bash
cd PostgreSQL-Learning/playbook-install-pg-cluster-docker-etcd/

# Phase 0: Validate ansible hosts
ansible-inventory -i hosts.yml --graph
ansible -i hosts.yml all --list-hosts
ansible -i hosts.yml primary_cluster --list-hosts
ansible -i hosts.yml standby_cluster --list-hosts

# Phase 1: Create Docker containers and network. Place logs in run_logs for analysis
ansible-playbook -i hosts.yml playbook-setup-standby-cluster-containers.yml 2>&1 | tee logs/playbook-setup-standby-cluster-containers.yml.log

# Phase 2: Setup Standby Patroni/PostgreSQL Cluster with one or more nodes
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml --vault-password-file=vault-pass \
  -e reinit_cluster=true 2>&1 | tee logs/playbook-install-standby-cluster.yml.log

# Phase 3: Verify Standby Cluster is Streaming
docker exec docpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list

# Expected output:
# | docpg-cls1-pg4 | 172.18.0.14 | Standby | streaming | TL | 0 MB | (secondary cluster) |

# Verify docpg-cls1-pg4 can reach primary cluster leader
docker exec docpg-cls1-pg4 psql -h 172.18.0.10 -p 5432 -U postgres -c "SELECT 1;"
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

Containers expose no host ports, so all psql access from the Mac goes through `docker exec`.
The steps below provide convenient shell wrappers and ensure passwords are sourced from
a single secret file rather than hard-coded anywhere.

### 1. ~/.vars_personal — secret source (chmod 600)

```bash
# Source of truth for the postgres superuser password. Loaded by ~/.zshrc.
export PG_SUPERUSER_PWD='<your-postgres-password>'    # match the Ansible vault value
```

Make sure this file is sourced from `~/.zshrc` (e.g. `[ -f ~/.vars_personal ] && source ~/.vars_personal`)
and has restrictive permissions: `chmod 600 ~/.vars_personal`.

### 2. ~/.pgpass — used INSIDE the containers (chmod 600)

Containers already have `/root/.pgpass` populated by the install playbook so that
`docker exec <container> psql ...` works without `PGPASSWORD`. If you also want host-side
psql to work (e.g. via `socat`/tunnel forwards you create ad-hoc), add this file on the Mac:

```
*:*:*:*:<your-postgres-password>
```

Wildcard entries cover all hostnames, ports, databases, and users.
Do not commit this file to git.

### 3. ~/.zshrc — dynamic shell functions

Add to `~/.zshrc`:

```zsh
# Resolve current primary/replica by querying Patroni REST via docker exec
_PG_NODES=(docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3)

# Connect to current Patroni primary — accepts any extra psql args
function pg-primary() {
  for _n in "${_PG_NODES[@]}"; do
    if docker exec "${_n}" curl -sf --max-time 2 http://127.0.0.1:8008/primary >/dev/null 2>&1; then
      echo "[pg-primary -> ${_n}]"
      docker exec -it "${_n}" psql -U postgres "$@"; return $?
    fi
  done; echo "ERROR: no primary found" >&2; return 1
}

# Connect to first available healthy replica
function pg-replica() {
  for _n in "${_PG_NODES[@]}"; do
    if docker exec "${_n}" curl -sf --max-time 2 http://127.0.0.1:8008/replica >/dev/null 2>&1; then
      echo "[pg-replica -> ${_n}]"
      docker exec -it "${_n}" psql -U postgres "$@"; return $?
    fi
  done; echo "ERROR: no replica found" >&2; return 1
}

# Print Patroni cluster state, Keepalived VIPs, and HAProxy backend health
function pg-status() {
  echo "=== Patroni cluster ==="
  for _n in "${_PG_NODES[@]}"; do
    docker exec "${_n}" patronictl -c /etc/patroni/patroni.yml list 2>/dev/null && break
  done

  echo ""
  echo "=== Keepalived VIPs ==="
  for _n in "${_PG_NODES[@]}"; do
    docker exec "${_n}" ip addr show eth0 2>/dev/null \
      | awk -v node="${_n}" '/inet / && !/172\.18\.0\.1[123]\//{printf "  %-20s <- %s\n", node, $2}'
  done

  echo ""
  echo "=== HAProxy backends (be_write / be_read) ==="
  for _n in "${_PG_NODES[@]}"; do
    if docker exec "${_n}" systemctl is-active haproxy >/dev/null 2>&1; then
      docker exec "${_n}" bash -c \
        'curl -s -u "admin:'"${PG_SUPERUSER_PWD}"'" "http://127.0.0.1:7000/;csv" \
         | grep -v "^#\|FRONTEND\|stats" | cut -d, -f1,2,18' 2>/dev/null
      break
    fi
  done
}

alias psql-pg1='docker exec -it docpg-cls1-pg1 psql -U postgres'
alias psql-pg2='docker exec -it docpg-cls1-pg2 psql -U postgres'
alias psql-pg3='docker exec -it docpg-cls1-pg3 psql -U postgres'
alias psql-pg4='docker exec -it docpg-cls1-pg4 psql -U postgres'
```

---

## Connecting to PostgreSQL

Containers expose no host ports. All connections from the Mac go through `docker exec`.
The container's `/root/.pgpass` handles authentication — no password in the command line.

### A. Direct psql — per node

```bash
# Container names match inventory_hostname in hosts.yml
docker exec -it docpg-cls1-pg1 psql -U postgres postgres    # leader (usually)
docker exec -it docpg-cls1-pg2 psql -U postgres postgres    # sync standby
docker exec -it docpg-cls1-pg3 psql -U postgres postgres    # replica (nosync)
```

### B. pgBouncer — per node

```bash
docker exec -it docpg-cls1-pg1 psql -h 127.0.0.1 -p 6432 -U postgres postgres
docker exec -it docpg-cls1-pg2 psql -h 127.0.0.1 -p 6432 -U postgres postgres
docker exec -it docpg-cls1-pg3 psql -h 127.0.0.1 -p 6432 -U postgres postgres
```

### C. Shell aliases (from Mac ~/.zshrc)

```bash
psql-pg1            # docker exec -it docpg-cls1-pg1 psql -U postgres
psql-pg2            # docker exec -it docpg-cls1-pg2 psql -U postgres
psql-pg3            # docker exec -it docpg-cls1-pg3 psql -U postgres
```

### D. Dynamic shell functions — role-based

These probe the Patroni REST API inside each container to find the current role.

```bash
pg-primary                                          # open psql on current leader
pg-primary -c "SELECT pg_is_in_recovery();"         # run query on leader
pg-primary -d dba -c "SELECT count(*) FROM ..."     # specific database

pg-replica                                          # open psql on first healthy replica
pg-replica -c "SELECT pg_last_wal_replay_lsn();"   # check replica lag

pg-status                                           # cluster overview (Patroni + VIPs + HAProxy)
```

### E. Via Keepalived VIPs (Docker-internal — from container exec)

VIPs float between containers. Accessible inside the Docker network only.

```bash
# Primary VIP (172.18.0.10) — always the Patroni leader
docker exec docpg-cls1-pg3 psql -h 172.18.0.10 -p 5432 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"

# Replica VIP (172.18.0.9) — highest-priority healthy replica
docker exec docpg-cls1-pg3 psql -h 172.18.0.9 -p 5432 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

### F. Via HAProxy + VIP (Docker-internal — best practice for applications)

HAProxy routes based on Patroni health check — write port goes only to primary,
read port goes only to replicas, regardless of which container's HAProxy you hit.

```bash
# Writes via primary VIP + HAProxy write port
docker exec docpg-cls1-pg3 psql -h 172.18.0.10 -p 5000 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"
# → always returns the primary node, is_replica=f

# Reads via primary VIP + HAProxy read port
docker exec docpg-cls1-pg3 psql -h 172.18.0.10 -p 5001 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"
# → always returns a replica, is_replica=t

# Reads via replica VIP + HAProxy read port
docker exec docpg-cls1-pg3 psql -h 172.18.0.9 -p 5001 -U postgres postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

### G. HAProxy stats UI (Docker-internal)

No host ports — open the stats page via socat or from inside a container:

```bash
# From inside any primary-cluster container
docker exec docpg-cls1-pg1 curl -s -u "admin:<PG_SUPERUSER_PWD>" \
  "http://127.0.0.1:7000/;csv" | grep -v "^#\|FRONTEND\|stats" | cut -d, -f1,2,18

# Or open an ad-hoc port forward on the Mac (socat required: brew install socat)
socat TCP-LISTEN:7000,fork \
  EXEC:"docker exec -i docpg-cls1-pg1 socat STDIO TCP:127.0.0.1:7000" &
open http://localhost:7000    # then kill the socat background job when done
```

---

## Patroni Status & Management

```bash
# Full cluster status (run from any node)
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list

# Cluster topology with history
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml topology

# Cluster event history (switchovers, failovers, timeline changes)
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml history docpg-cls1

# Replication lag check
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list | grep -E "Lag|Member"

# Show current cluster config (DCS-stored parameters)
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml show-config

# Edit DCS-stored cluster config
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml edit-config

# Patroni REST API — health check on each node (via docker exec since no host ports)
docker exec docpg-cls1-pg1 curl -s http://127.0.0.1:8008/patroni | python3 -m json.tool
docker exec docpg-cls1-pg2 curl -s http://127.0.0.1:8008/patroni | python3 -m json.tool
docker exec docpg-cls1-pg3 curl -s http://127.0.0.1:8008/patroni | python3 -m json.tool

# Check which node is primary (returns HTTP 200 only on primary, 503 otherwise)
docker exec docpg-cls1-pg1 curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary
docker exec docpg-cls1-pg2 curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary
docker exec docpg-cls1-pg3 curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary

# Check which nodes are healthy replicas
docker exec docpg-cls1-pg1 curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/replica
docker exec docpg-cls1-pg3 curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/replica

# Switchover (graceful, requires a leader)
# IMPORTANT: cluster name is a required positional argument; omitting it triggers interactive
# mode which aborts with "Aborted!" when Enter is pressed with no input.
# --force suppresses the interactive confirmation prompt.
# --leader    = current primary to step down   (check with: patronictl list)
# --candidate = replica to promote; either docpg-cls1-pg1 or docpg-cls1-pg2 can be leader
# Example (replace <current-leader> and <candidate> with actual node names):
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml switchover docpg-cls1 \
  --leader <current-leader> --candidate <candidate> --force

# Trigger a manual failover (promotes a replica to leader)
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml failover docpg-cls1 --force

# Failover to a specific node
# NOTE: Patroni 4.x uses --leader instead of the deprecated --master flag
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml failover docpg-cls1 \
  --leader docpg-cls1-pg2 --candidate docpg-cls1-pg1 --force

# Pause/resume Patroni automatic failover
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml pause
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml resume

# Reload Patroni config after editing patroni.yml
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml reload docpg-cls1

# Reinitialize a lagging/diverged replica
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml reinit docpg-cls1 docpg-cls1-pg1 --force
```

---

## PostgreSQL Status

```bash
# Connect to specific node (use pg-primary / pg-replica functions for role-based access)
docker exec -it docpg-cls1-pg1 psql -U postgres postgres   # leader (usually)
docker exec -it docpg-cls1-pg2 psql -U postgres postgres   # sync standby
docker exec -it docpg-cls1-pg3 psql -U postgres postgres   # replica (nosync)

# Replication status — lag in seconds and bytes (run on primary — docpg-cls1-pg1)
# write_lag  : primary flush → standby wrote WAL to OS buffer  (network RTT)
# flush_lag  : primary flush → standby flushed WAL to disk     (commit overhead for sync standby)
# replay_lag : primary flush → standby applied WAL to data     (replica data staleness)
# replication_lag_sec: replay_lag when active; 0 when idle and fully caught up (lag_mb=0)
docker exec docpg-cls1-pg1 psql -U postgres postgres -c "
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

# Check standby recovery status (run on replica — docpg-cls1-pg2 or docpg-cls1-pg3)
# replication_delay: seconds since last transaction was replayed on this replica
docker exec docpg-cls1-pg2 psql -U postgres postgres -c "
  SELECT pg_is_in_recovery(),
         extract(epoch FROM (now() - pg_last_xact_replay_timestamp()))::numeric(10,3) AS replication_delay_sec,
         pg_last_wal_receive_lsn(),
         pg_last_wal_replay_lsn(),
         round((pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())) / 1048576.0, 2) AS receive_vs_replay_lag_mb;"

# Active connections and sessions (run on primary — docpg-cls1-pg1)
docker exec docpg-cls1-pg1 psql -U postgres postgres -c "
  SELECT count(*), state, wait_event_type, wait_event
  FROM pg_stat_activity GROUP BY state, wait_event_type, wait_event ORDER BY count DESC;"

# Long-running queries (>30s) (run on primary — docpg-cls1-pg1)
docker exec docpg-cls1-pg1 psql -U postgres postgres -c "
  SELECT pid, now()-query_start AS duration, state, left(query,80) AS query
  FROM pg_stat_activity
  WHERE state != 'idle' AND query_start < now() - interval '30 seconds'
  ORDER BY duration DESC;"

# pg_stat_statements top 10 by total time (run on primary — docpg-cls1-pg1)
docker exec docpg-cls1-pg1 psql -U postgres postgres -c "
  SELECT round(total_exec_time::numeric,2) AS total_ms,
         calls, round(mean_exec_time::numeric,2) AS mean_ms,
         left(query,80) AS query
  FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;"

# Database sizes
docker exec docpg-cls1-pg1 psql -U postgres postgres -c "
  SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY 2 DESC;"

# Table bloat (top 10)
docker exec docpg-cls1-pg1 psql -U postgres postgres -c "
  SELECT schemaname, tablename,
         pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
         n_dead_tup, n_live_tup
  FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10;"
```

---

## HAProxy Status & Management

```bash
# HAProxy backend health summary (CSV stats from inside a container)
docker exec docpg-cls1-pg2 bash -c \
  'curl -s -u "admin:<PG_SUPERUSER_PWD>" "http://127.0.0.1:7000/;csv" \
   | grep -v "^#" | cut -d, -f1,2,18 \
   | awk -F, '"'"'{printf "%-12s %-8s %s\n", $1, $2, $3}'"'"''

# Full stats page (open in browser after port-forwarding)
# From inside container: http://172.18.0.12:7000/  (admin / <PG_SUPERUSER_PWD>)

# Check which backends are UP (for write port)
docker exec docpg-cls1-pg2 bash -c \
  'curl -s -u "admin:<PG_SUPERUSER_PWD>" "http://127.0.0.1:7000/;csv" \
   | grep "be_write" | cut -d, -f1,2,18 \
   | awk -F, '"'"'{printf "%-12s %-8s %s\n", $1, $2, $3}'"'"''

# Check which backends are UP (for read port)
docker exec docpg-cls1-pg2 bash -c \
  'curl -s -u "admin:<PG_SUPERUSER_PWD>" "http://127.0.0.1:7000/;csv" \
   | grep "be_read" | cut -d, -f1,2,18 \
   | awk -F, '"'"'{printf "%-12s %-8s %s\n", $1, $2, $3}'"'"''

# HAProxy service status on each node
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ==="; docker exec $n systemctl status haproxy --no-pager -l | tail -3
done

# Reload HAProxy config (no connection drops, used after config change)
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do docker exec $n systemctl reload haproxy; done

# Verify HAProxy write port routes only to primary
docker exec docpg-cls1-pg3 psql -h 172.18.0.10 -p 5000 \
  -U postgres -d postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"

# Verify HAProxy read port routes only to replica
docker exec docpg-cls1-pg3 psql -h 172.18.0.10 -p 5001 \
  -U postgres -d postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

---

## Keepalived Status & Management

```bash
# Which node holds each VIP
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n ip addr show eth0 | grep "inet "
done
# 172.18.0.10 (eth0:vip)    → Patroni primary (leader)
# 172.18.0.9  (eth0:rvip)   → sync standby (Keepalived uses /synchronous endpoint)

# Keepalived service status
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n systemctl status keepalived --no-pager | tail -5
done

# VRRP state on each node (MASTER vs BACKUP)
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n: "
  docker exec $n journalctl -u keepalived --no-pager -n 5 2>/dev/null \
    | grep -E "MASTER|BACKUP" | tail -2
done

# Keepalived effective priorities (shows weight contribution)
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n primary check: "
  docker exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary
  echo -n "  replica check: "
  docker exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/replica
  echo
done

# Manually verify VIP reachability from inside cluster
docker exec docpg-cls1-pg3 ping -c 2 172.18.0.10   # primary VIP
docker exec docpg-cls1-pg3 ping -c 2 172.18.0.9    # replica VIP

# Restart Keepalived (re-triggers VRRP election)
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do docker exec $n systemctl restart keepalived; done
# Wait ~8s for election to settle then re-check VIP assignment
```

---

## pgBouncer Status & Management

```bash
# pgBouncer admin console (via docker exec — no host ports needed)
docker exec docpg-cls1-pg1 psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c "SHOW POOLS;"
docker exec docpg-cls1-pg2 psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c "SHOW POOLS;"
docker exec docpg-cls1-pg3 psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c "SHOW POOLS;"

# All useful pgBouncer admin commands (run on any node)
docker exec -it docpg-cls1-pg2 psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer << 'EOF'
SHOW CLIENTS;
SHOW SERVERS;
SHOW STATS;
SHOW POOLS;
SHOW DATABASES;
SHOW CONFIG;
EOF

# pgBouncer service status
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n systemctl status pgbouncer --no-pager | tail -3
done

# Reload pgBouncer after config change
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do docker exec $n systemctl reload pgbouncer; done

# Fix stale connection pool (SASL auth failures after failover)
# This clears all server-side connections and forces reconnects
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "Reconnecting $n pgBouncer pools..."
  docker exec $n psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c "RECONNECT;" 2>/dev/null \
  || docker exec $n systemctl reload pgbouncer
done

# Check which PostgreSQL host each pgBouncer is pointing to
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n pgbouncer → " && docker exec $n grep "^*" /etc/pgbouncer/pgbouncer.ini
done
```

---

## etcd Status & Management

```bash
# etcd cluster member list (from inside container)
docker exec docpg-cls1-pg1 etcdctl --endpoints=http://172.18.0.11:2379 member list

# etcd cluster health
docker exec docpg-cls1-pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health

# etcd endpoint status (leader, raft term, raft index)
docker exec docpg-cls1-pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint status --write-out=table

# Read Patroni DCS key
docker exec docpg-cls1-pg1 etcdctl --endpoints=http://172.18.0.11:2379 \
  get /service/docpg-cls1/leader

# etcd service status
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n systemctl status etcd --no-pager | tail -3
done
```

---

## pgBackRest Status & Management

```bash
# Show backup info (run from any node with access to shared volume)
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 info

# Full backup (run on leader — docpg-cls1-pg1)
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 --log-level-console=info backup --type=full

# Incremental backup
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 --log-level-console=info backup --type=incr

# Differential backup
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 --log-level-console=info backup --type=diff

# Check backup integrity
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 check

# Restore (stop patroni first, then restore, then restart)
docker exec docpg-cls1-pg1 systemctl stop patroni
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 --log-level-console=info restore --delta
docker exec docpg-cls1-pg1 systemctl start patroni

# Point-in-time restore
docker exec docpg-cls1-pg1 systemctl stop patroni
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 --log-level-console=info restore --delta \
  --target="2026-04-30 10:30:00" --target-action=promote
docker exec docpg-cls1-pg1 systemctl start patroni
```

---

## Log Inspection

All commands use `docker exec` so they work from the Mac host terminal without SSH.

### PostgreSQL logs

```bash
# Tail PostgreSQL log on the current leader (docpg-cls1-pg1)
docker exec docpg-cls1-pg1 tail -100 /var/log/postgresql/postgresql-Wed.log

# Follow PostgreSQL log live
docker exec docpg-cls1-pg1 bash -c "tail -f /var/log/postgresql/postgresql-$(date +%a).log"

# Search for errors in PostgreSQL log
docker exec docpg-cls1-pg1 grep -i "ERROR\|FATAL\|PANIC" /var/log/postgresql/postgresql-Wed.log | tail -20

# PostgreSQL log on all nodes
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n bash -c \
    "tail -20 /var/log/postgresql/postgresql-\$(date +%a).log 2>/dev/null || echo 'no log'"
done
```

### Patroni logs

```bash
# Patroni log on all nodes
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n tail -30 /var/log/patroni/patroni.log
done

# Follow Patroni log live on leader
docker exec docpg-cls1-pg1 tail -f /var/log/patroni/patroni.log

# Patroni log via journald
docker exec docpg-cls1-pg1 journalctl -u patroni --no-pager -n 50

# Search for failover/switchover events
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n grep -i "promoting\|demoting\|failover\|switchover\|leader" \
    /var/log/patroni/patroni.log | tail -10
done
```

### HAProxy logs

```bash
# HAProxy logs via journald
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u haproxy --no-pager -n 20
done

# Follow HAProxy log live
docker exec docpg-cls1-pg1 journalctl -u haproxy -f

# Check backend state changes in HAProxy log
docker exec docpg-cls1-pg1 journalctl -u haproxy --no-pager | grep -i "UP\|DOWN\|BACKEND"
```

### Keepalived logs

```bash
# Keepalived VRRP election and VIP assignment events
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u keepalived --no-pager -n 20
done

# Follow Keepalived log live (watch VIP migrations)
docker exec docpg-cls1-pg1 journalctl -u keepalived -f

# Show only MASTER/BACKUP transitions
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n: " && docker exec $n journalctl -u keepalived --no-pager \
    | grep -E "MASTER STATE|BACKUP STATE" | tail -3
done
```

### pgBouncer logs

```bash
# pgBouncer log on all nodes
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n tail -20 /var/log/pgbouncer/pgbouncer.log
done

# Follow pgBouncer log live
docker exec docpg-cls1-pg1 tail -f /var/log/pgbouncer/pgbouncer.log

# Search for auth errors
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n grep -i "ERROR\|failed\|refused" \
    /var/log/pgbouncer/pgbouncer.log | tail -5
done
```

### pgBackRest logs

```bash
# pgBackRest backup log
docker exec docpg-cls1-pg1 cat /var/log/pgbackrest/docpg-cls1-backup.log 2>/dev/null | tail -30

# List all pgBackRest logs
docker exec docpg-cls1-pg1 ls /var/log/pgbackrest/

# Check stanza status and health
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 info
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 check

# Check stanza details (system-id, wal_system_identifier, etc.)
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 info --log-level-console=info
```

### etcd logs

```bash
# etcd logs via journald
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u etcd --no-pager -n 15
done

# etcd leader election events
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u etcd --no-pager \
    | grep -i "elected\|leader\|follower" | tail -5
done
```

---

## Health Validation Cheatsheet

```bash
# 1. Patroni cluster state
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list

# 2. VIP locations
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n: " && docker exec $n ip addr show eth0 | grep "inet " | awk '{print $2}'
done

# 3. HAProxy backend health (1 line per backend)
docker exec docpg-cls1-pg2 bash -c \
  'curl -s -u "admin:<PG_SUPERUSER_PWD>" "http://127.0.0.1:7000/;csv" \
   | grep -v "^#\|FRONTEND" | cut -d, -f1,2,18'

# 4. Write path: confirm connection lands on primary
docker exec docpg-cls1-pg3 psql -h 172.18.0.10 -p 5000 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"

# 5. Read path: confirm connection lands on a replica
docker exec docpg-cls1-pg3 psql -h 172.18.0.10 -p 5001 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"

# 6. Direct PG connectivity on each node
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n → "
  docker exec $n psql -U postgres postgres -c "SELECT pg_is_in_recovery();" -t 2>&1 | tr -d ' \n'
  echo
done

# 7. etcd health
docker exec docpg-cls1-pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health

# 8. pgBackRest stanza check
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 check
```

---

## Troubleshooting

### pgBouncer SASL authentication failed

Symptom: `FATAL: SASL authentication failed` when connecting through pgBouncer.

Cause: Stale server-side pool connections (common after a Patroni failover/restart).

```bash
# Fix: reload pgBouncer to clear stale connections
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do docker exec $n systemctl reload pgbouncer; done
```

### Keepalived VIP not assigned (silent failure)

Symptom: `ip addr show eth0` shows no VIP despite Keepalived running.

Common cause: Interface label too long (Linux limit: 15 chars). Check the log:

```bash
docker exec docpg-cls1-pg1 journalctl -u keepalived --no-pager | grep -i "label\|removing\|no VIP"
```

Fix: Ensure labels in `keepalived.conf.j2` are ≤15 chars (e.g., `eth0:vip`, `eth0:rvip`).

### HAProxy backend shows all DOWN

Symptom: All backends DOWN in `be_write` or `be_read`.

```bash
# Check if Patroni REST API is reachable
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n /primary: "
  docker exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary
  echo
done

# Restart HAProxy if needed
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do docker exec $n systemctl restart haproxy; done
```

### Patroni failover not happening

```bash
# Check if Patroni is paused
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list | grep -i pause

# Resume if paused
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml resume

# Check etcd connectivity (DCS required for failover)
docker exec docpg-cls1-pg2 etcdctl --endpoints=http://172.18.0.12:2379 endpoint health
```

### Replica lagging behind

```bash
# Check lag
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml list

# Reinitialize lagging replica from scratch
docker exec docpg-cls1-pg2 patronictl -c /etc/patroni/patroni.yml reinit docpg-cls1 docpg-cls1-pg3 --force
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
# Enter the leader container and switch to postgres user
docker exec -it docpg-cls1-pg1 bash
su - postgres

# Delete the old stanza (all backups for this stanza will be removed)
pgbackrest --stanza=docpg-cls1 stanza-delete --force

# Create a new stanza synchronized with the current PostgreSQL instance
pgbackrest --stanza=docpg-cls1 stanza-create

# Verify the stanza is now valid
pgbackrest --stanza=docpg-cls1 check

# Exit back to root
exit
exit

# Now run a full backup
docker exec docpg-cls1-pg1 pgbackrest --stanza=docpg-cls1 --log-level-console=info backup --type=full
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
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list

# Check current VIP assignments
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n: "
  docker exec $n ip addr show eth0 | grep "inet " | awk '{print $2}' | tr '\n' ' '; echo
done

# Restart Keepalived on the primary node to re-acquire the VIP
docker exec <primary_node> systemctl restart keepalived
sleep 5

# Verify VIP is now assigned
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n: "
  docker exec $n ip addr show eth0 | grep "inet " | awk '{print $2}' | tr '\n' ' '; echo
done
```

### HAProxy ports not reachable inside container

Symptom: Unable to reach HAProxy ports (5000/5001/7000) from within a container.

Cause: HAProxy service is not running or failed to start on that node.

```bash
# Check HAProxy status on all nodes
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  echo -n "$n: "
  docker exec $n systemctl is-active haproxy
done

# Restart HAProxy if needed
for n in docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3; do
  docker exec $n systemctl restart haproxy
done
```

### psql password authentication failed despite correct ~/.pgpass

Symptom: `FATAL: password authentication failed` even though `/root/.pgpass` has the right entry.

Cause: The `PGPASSWORD` environment variable takes precedence over `~/.pgpass`. If it is set to an
old or wrong value in the container environment, it will override the password file silently.

```bash
# Check if PGPASSWORD is set inside the container
docker exec docpg-cls1-pg1 env | grep PGPASSWORD

# Verify /root/.pgpass has correct entries and permissions
docker exec docpg-cls1-pg1 cat /root/.pgpass
docker exec docpg-cls1-pg1 ls -la /root/.pgpass   # must be 600
```

### Writes hanging / primary blocked waiting for sync standby

Symptom: write queries hang indefinitely; `pg_stat_replication` shows `sync_state = sync` for the
sync standby but `sent_lsn != flush_lsn`.

Cause: The sync standby (whichever of docpg-cls1-pg1/pg2 holds that role) is down or lagging. The primary
waits for it to confirm WAL receipt before committing (`synchronous_commit = on`,
`synchronous_node_count = 1`).

```bash
# Check replication state on primary — use patronictl list to identify it first
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
docker exec docpg-cls1-pg1 psql -U postgres postgres \
  -c "SELECT client_addr, state, sync_state, sent_lsn, flush_lsn FROM pg_stat_replication;"

# Check Patroni status on the sync standby node
docker exec <sync-standby-node> systemctl status patroni

# If the sync standby is down and you need writes to continue immediately — temporarily switch to async:
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml edit-config docpg-cls1 \
  --force -p synchronous_mode=false
# Restore sync mode once the sync standby is back and caught up:
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml edit-config docpg-cls1 \
  --force -p synchronous_mode=true
```

### Container won't start after Docker Desktop restart

```bash
docker start docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3
sleep 5
# Services (patroni, etcd, pgbouncer, haproxy, keepalived) are enabled and auto-start
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

### etcd quorum lost (2 of 3 nodes down)

The cluster becomes read-only (no Patroni operations). Restart at least 2 nodes:

```bash
docker start docpg-cls1-pg1 docpg-cls1-pg2
sleep 10
docker exec docpg-cls1-pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379 \
  endpoint health
```

---

---

## Common Ansible Operations

```bash
cd playbook-install-pg-cluster-docker-etcd/

# Full cluster install (Phase 1 + Phase 2)
ansible-playbook -i hosts.yml playbook-setup-primary-cluster-containers.yml
ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml --vault-password-file=vault-pass

# Install/reconfigure a single component only
ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml \
  --vault-password-file=vault-pass --tags haproxy
ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml \
  --vault-password-file=vault-pass --tags keepalived
ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml \
  --vault-password-file=vault-pass --tags haproxy,keepalived
ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml \
  --vault-password-file=vault-pass --tags patroni
ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml \
  --vault-password-file=vault-pass --tags pgbackrest
ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml \
  --vault-password-file=vault-pass --tags etcd

# Reinitialize cluster (DESTROYS ALL DATA — keeps packages)
ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true

# Reinitialize + wipe all pgBackRest backups
ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml \
  --vault-password-file=vault-pass \
  -e reinit_cluster=true -e cleanup_pgbackrest_backups=true

# Edit vault credentials
ansible-vault edit sensitive-values --vault-password-file=vault-pass

# Enter containers interactively (no SSH needed — Docker connection plugin)
docker exec -it docpg-cls1-pg1 bash
docker exec -it docpg-cls1-pg2 bash
docker exec -it docpg-cls1-pg3 bash

# Stop/start all pg containers
docker stop docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3 && \
  docker start docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3

# Full teardown — WARNING: destroys all data
docker rm -f docpg-cls1-pg1 docpg-cls1-pg2 docpg-cls1-pg3
docker volume rm pg-data-docpg-cls1-pg1 pg-data-docpg-cls1-pg2 pg-data-docpg-cls1-pg3 \
                 pg-logs-docpg-cls1-pg1 pg-logs-docpg-cls1-pg2 pg-logs-docpg-cls1-pg3 pg-backups
```

---

## Prometheus Scrape Config

```yaml
# Note: postgres_exporter ports are not mapped to the Mac host (no host port mappings).
# To scrape metrics, run a Prometheus container on the same Docker network (lab-network)
# and target the container IPs directly.
scrape_configs:
  - job_name: postgresql_docker
    static_configs:
      - targets:
          - '172.18.0.11:9187'   # docpg-cls1-pg1
          - '172.18.0.12:9187'   # docpg-cls1-pg2
          - '172.18.0.13:9187'   # docpg-cls1-pg3
        labels:
          cluster: docpg-cls1
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

- **No host-mapped ports**: Containers expose no ports to the Mac host. All management commands
  use `docker exec` directly. Ansible uses `community.docker.docker` connection plugin, which
  also routes through `docker exec` — no SSH or port 22 mapping required.

- **Synchronous replication**: `synchronous_mode: true` with `synchronous_node_count: 1` — every
  commit on the leader must be acknowledged by the sync standby (whichever of docpg-cls1-pg1/pg2 holds that
  role) before returning to the client. docpg-cls1-pg3 is excluded via `nosync: true` and never holds the sync
  standby role. If the sync standby goes down, writes on the leader will block until it recovers (or
  sync mode is temporarily disabled via `patronictl edit-config`). Failover between docpg-cls1-pg1 and docpg-cls1-pg2 is
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
ajaydwivedi@Ajays-MacBook-Pro PostgreSQL-Learning % docker exec -it docpg-cls1-pg2 bash
root@docpg-cls1-pg2:/# patronictl -c /etc/patroni/patroni.yml list
+ Cluster: docpg-cls1 (7634451494908218688) ----+-----------+
| Member             | Host        | Role    | State     | TL | Lag in MB |
+--------------------+-------------+---------+-----------+----+-----------+
| docpg-cls1-pg1     | 172.18.0.11 | Replica | streaming |  2 |         0 |
| docpg-cls1-pg2     | 172.18.0.12 | Leader  | running   |  2 |           |
| docpg-cls1-pg3     | 172.18.0.13 | Replica | streaming |  2 |         0 |
+--------------------+-------------+---------+-----------+----+-----------+
root@docpg-cls1-pg2:/#
root@docpg-cls1-pg2:/# su - postgres
postgres@docpg-cls1-pg2:~$ psql
psql (18.3 (Ubuntu 18.3-1.pgdg24.04+1))
Type "help" for help.

postgres=#
postgres=# \q
postgres@docpg-cls1-pg2:~$ exit
logout
root@docpg-cls1-pg2:/#

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
172.18.0.11  docpg-cls1-pg1    # PostgreSQL :5432  Patroni :8008
172.18.0.12  docpg-cls1-pg2    # PostgreSQL :5432  Patroni :8008
172.18.0.13  docpg-cls1-pg3    # PostgreSQL :5432  Patroni :8008

172.18.0.10 pg-primary pg-leader
172.18.0.9  pg-replica
EOF
```

### Run patronictl from Mac host without entering container
```bash
# List cluster state (no SSH needed — docker exec is sufficient)
docker exec docpg-cls1-pg1 patronictl -c /etc/patroni/patroni.yml list
```

# Augment Instructions
```
playbook failed again. 

ansible-playbook -i hosts.yml playbook-setup-standby-cluster-containers.yml 2>&1 | tee logs/playbook-setup-standby-cluster-containers.yml.log

check playbook log file. 
Scan patroni, postgresql, etcd logs, journalctl logs on all replicas between start & end of playbook run.
Then perform following action -
- Provide RCA for failure
- Fix playbook tasks

After you are done with file changes, re-validate file changes again as if you are trying to find issues in changes made by other person. And if you find any issue, fix it.

It is very important that leader or standby leader node should NOT go down during this process. If it goes down, then client loses trust in us DBAs.

Then again perform the cycle of re-validating files changes like a senior engineer will do on a junior engineer's changes.

Remember -> Any self-help document you create for yourself should go in .augment directory.

```
