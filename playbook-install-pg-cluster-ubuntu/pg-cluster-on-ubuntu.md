# PostgreSQL HA Cluster on Ubuntu

> **Stack:** PostgreSQL 17 · Patroni 4.0.6 · Consul 1.21.3 · pgBackRest · SMB shared storage
>
> **Reference:** [Patroni and pgBackRest combined](https://pgstef.github.io/2022/07/12/patroni_and_pgbackrest_combined.html)

---

## Table of Contents

- [PostgreSQL HA Cluster on Ubuntu](#postgresql-ha-cluster-on-ubuntu)
  - [Table of Contents](#table-of-contents)
  - [1. Architecture](#1-architecture)
    - [Replication Flow](#replication-flow)
    - [WAL Archiving Flow](#wal-archiving-flow)
  - [2. Components](#2-components)
    - [2.1 PostgreSQL 17](#21-postgresql-17)
    - [2.2 Patroni](#22-patroni)
    - [2.3 Consul](#23-consul)
    - [2.4 pgBackRest](#24-pgbackrest)
    - [2.5 SMB Shared Storage](#25-smb-shared-storage)
  - [3. Cluster Topology](#3-cluster-topology)
  - [4. Setup — Primary Cluster (DC1)](#4-setup--primary-cluster-dc1)
    - [Prerequisites](#prerequisites)
    - [Inventory](#inventory)
    - [Run the playbook](#run-the-playbook)
    - [What the playbook does (in order)](#what-the-playbook-does-in-order)
    - [Verify after setup](#verify-after-setup)
  - [5. Setup — Standby Cluster (DC2)](#5-setup--standby-cluster-dc2)
    - [Run the playbook](#run-the-playbook-1)
    - [Key differences from primary cluster](#key-differences-from-primary-cluster)
    - [Verify after setup](#verify-after-setup-1)
    - [Reinitialise a stuck replica](#reinitialise-a-stuck-replica)
  - [6. Switchover \& Failover](#6-switchover--failover)
    - [6.1 Planned Switchover (DC1 → DC2)](#61-planned-switchover-dc1--dc2)
    - [6.2 Disaster Recovery — DC1 goes offline](#62-disaster-recovery--dc1-goes-offline)
    - [6.3 Restoring DC1 as New Standby after DR](#63-restoring-dc1-as-new-standby-after-dr)
  - [7. Backup \& Restore with pgBackRest](#7-backup--restore-with-pgbackrest)
    - [Take a backup (run as `postgres` on the primary)](#take-a-backup-run-as-postgres-on-the-primary)
    - [Via Ansible (from control node)](#via-ansible-from-control-node)
    - [Switch between SMB and S3 repositories](#switch-between-smb-and-s3-repositories)
  - [8. Consul UI](#8-consul-ui)
  - [9. Troubleshooting](#9-troubleshooting)
    - [Cluster health](#cluster-health)
    - [Service management](#service-management)
    - [Patroni operations](#patroni-operations)
    - [pgBackRest](#pgbackrest)
    - [SMB share](#smb-share)
    - [Logs](#logs)

---

## 1. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Hypervisor: ryzen9                           │
│   DC1 NIC: 192.168.100.1          DC2 NIC: 192.168.200.1           │
│   SMB Share: /stale-storage/share-stalestorage (guest, Everyone:F) │
└───────────────────────────┬─────────────────────┬───────────────────┘
                            │                     │
          ┌─────────────────▼──────┐   ┌──────────▼─────────────────┐
          │   DC1 — Primary Cluster│   │  DC2 — Standby Cluster     │
          │   192.168.100.0/24     │   │  192.168.200.0/24          │
          │                        │   │                            │
          │  pg-cls1-prod0 (.42)   │   │  pg-cls1-dr0 (.42)        │
          │  pg-cls1-prod1 (.43) ◄─┼───┼──streaming replication──► │
          │  pg-cls1-prod2 (.44)   │   │  pg-cls1-dr1 (.43)        │
          │                        │   │  pg-cls1-dr2 (.44)        │
          │  Patroni scope:        │   │  Patroni scope:            │
          │  pg-cls1-prod          │   │  pg-cls1-dr                │
          └────────────┬───────────┘   └────────────┬───────────────┘
                       │                            │
                       └──────────┬─────────────────┘
                                  │
                     ┌────────────▼──────────────┐
                     │  Consul Server             │
                     │  pg-consul-rhel            │
                     │  192.168.100.41            │
                     │  datacenter: dc1           │
                     │  :8500/ui/dc1/services     │
                     └───────────────────────────┘
```

### Replication Flow

```
pg-cls1-prod1 (Leader/Primary, TL current)
    │
    ├──► pg-cls1-prod0 (Sync Standby, streaming, lag=0)
    ├──► pg-cls1-prod2 (Async Replica, streaming, lag=0)
    │
    └──► pg-cls1-dr1   (Standby Leader → cascades to dr0, dr2)
              ├──► pg-cls1-dr0
              └──► pg-cls1-dr2
```

### WAL Archiving Flow

```
pg-cls1-prod1 (primary)
    │  archive_command: pgbackrest archive-push
    ▼
SMB Share on ryzen9
/stale-storage/share-stalestorage/pgbackrest_backups/
    │  restore_command: pgbackrest archive-get
    ▼
All standbys (prod0, prod2, dr0, dr1, dr2)
```

---

## 2. Components

### 2.1 PostgreSQL 17

The database engine. Each node runs PostgreSQL 17 managed entirely by Patroni (not by the system `postgresql` service).

| Parameter | Value |
|-----------|-------|
| Version | 17 |
| Data directory | `/var/lib/postgresql/17/main` |
| Config directory | `/var/lib/postgresql/17/main` |
| Log directory | `/var/log/postgresql` |
| Port | `5432` |
| `max_connections` | `200` |
| `shared_buffers` | 25% of RAM |
| `effective_cache_size` | 75% of RAM |
| `wal_level` | `replica` |
| `archive_mode` | `on` |
| `synchronous_commit` | `on` |
| `max_wal_senders` | `10` |
| `max_replication_slots` | `10` |
| `shared_preload_libraries` | `pg_stat_statements, pg_cron` |

Key extensions installed: `pg_stat_statements`, `pg_cron`, `pg_partman`, `pg_repack`, `pgTAP`, `plpgsql_check`, `pg_qualstats`, `pg_permissions`.

### 2.2 Patroni

Patroni is the HA orchestrator. It manages leader election, failover, replica bootstrapping, and PostgreSQL configuration via DCS (Consul).

| Parameter | Value |
|-----------|-------|
| Version | `4.0.6` |
| Config file | `/etc/patroni/patroni.yml` |
| REST API port | `8008` |
| Log directory | `/var/log/patroni` |
| DCS | Consul |
| TTL | `30s` |
| Loop wait | `10s` |
| Retry timeout | `10s` |
| Max lag on failover | `1 MB` |
| Watchdog | `automatic` (`/dev/watchdog`) |
| `use_pg_rewind` | `true` |
| Synchronous mode | `on` (1 sync standby required) |

Replica bootstrap methods (in order):
1. `pgbackrest` — delta restore from SMB archive
2. `basebackup` — fallback `pg_basebackup` at 100 MB/s

Patroni REST API endpoints (per node):
```
http://<node>:8008/          # full node state (JSON)
http://<node>:8008/health    # 200 = healthy
http://<node>:8008/primary   # 200 only on the primary
http://<node>:8008/replica   # 200 only on replicas
```

### 2.3 Consul

Consul is the Distributed Configuration Store (DCS). Patroni uses it for leader election and cluster state.

| Parameter | Value |
|-----------|-------|
| Version | `1.21.3` |
| Server | `pg-consul-rhel` · `192.168.100.41` |
| Datacenter | `dc1` |
| Domain | `lab.com` |
| HTTP UI | `http://pg-consul-rhel:8500/ui/dc1/services` |
| Patroni key prefix | `/service/` |

Consul stores per-cluster keys under:
```
/service/pg-cls1-prod/leader        ← which node holds the lock
/service/pg-cls1-prod/config        ← dynamic DCS configuration
/service/pg-cls1-prod/optime/leader ← last applied LSN
/service/pg-cls1-dr/...             ← same for standby cluster
```

### 2.4 pgBackRest

pgBackRest performs WAL archiving and base backups.

| Parameter | Value |
|-----------|-------|
| Version | `2.56.0` |
| Config file | `/etc/pgbackrest/pgbackrest.conf` |
| Stanza name | `pg-cls1` |
| Repo type | `posix` (SMB share) |
| Repo path | `/stale-storage/share-stalestorage/pgbackrest_backups` |
| Compression | `zst` level 3 |
| `process-max` | `4` |
| `archive-async` | `on` |
| Spool path | `/var/spool/pgbackrest` |
| Full backup retention | `7` |
| Archive retention type | `full` |

Key commands:
```bash
# Run as postgres user on the primary
pgbackrest --stanza=pg-cls1 --type=full backup      # full backup
pgbackrest --stanza=pg-cls1 --type=diff backup      # differential backup
pgbackrest --stanza=pg-cls1 info                    # list backups
pgbackrest --stanza=pg-cls1 check                   # verify archive is working
pgbackrest --stanza=pg-cls1 stanza-create           # initialise stanza (once)
```

### 2.5 SMB Shared Storage

The pgBackRest repository is hosted on the hypervisor (`ryzen9`) via a Samba guest share.

| Parameter | Value |
|-----------|-------|
| Hypervisor host | `ryzen9` |
| DC1 IP | `192.168.100.1` |
| DC2 IP | `192.168.200.1` |
| Share name | `share-stalestorage` |
| Server path | `/stale-storage/share-stalestorage` |
| Mount point (all nodes) | `/stale-storage/share-stalestorage` |
| Auth | guest (no credentials) |
| SMB version | `3.0` |
| Mount options | `mfsymlinks,guest,uid=<postgres>,gid=<postgres>,file_mode=0640,dir_mode=0750,vers=3.0,_netdev,nofail` |
| `mfsymlinks` | Required for pgBackRest `latest` symlink |
| Samba `force create mode` | `0777` |
| Samba `force directory mode` | `0777` |

The share is mounted persistently via `/etc/fstab` on all 6 nodes. Each DC uses its own subnet IP for the server so routing stays local.

---

## 3. Cluster Topology

| Node | IP (DC1) | IP (DC2) | Role | Patroni Scope |
|------|----------|----------|------|---------------|
| `pg-cls1-prod0` | `192.168.100.42` | — | Sync Standby | `pg-cls1-prod` |
| `pg-cls1-prod1` | `192.168.100.43` | — | **Leader (Primary)** | `pg-cls1-prod` |
| `pg-cls1-prod2` | `192.168.100.44` | — | Async Replica | `pg-cls1-prod` |
| `pg-cls1-dr0` | — | `192.168.200.42` | Standby Replica | `pg-cls1-dr` |
| `pg-cls1-dr1` | — | `192.168.200.43` | **Standby Leader** | `pg-cls1-dr` |
| `pg-cls1-dr2` | — | `192.168.200.44` | Standby Replica | `pg-cls1-dr` |
| `pg-consul-rhel` | `192.168.100.41` | — | Consul Server | — |
| `ryzen9` | `192.168.100.1` | `192.168.200.1` | Hypervisor / SMB storage | — |

---

## 4. Setup — Primary Cluster (DC1)

### Prerequisites

- Ubuntu nodes with SSH access via `ansible` user (sudo, no password)
- Consul server running at `192.168.100.41`
- Vault-encrypted `sensitive-values` file with credentials
- `vars/dba_vars.yml` with hardware/tuning variables

### Inventory

```bash
# hosts__primary_cluster.yml — DC1 only
# hosts__multi_datacenter.yml — both DCs
```

### Run the playbook

```bash
cd ~/GitHub/PostgreSQL-Learning/playbook-install-pg-cluster-ubuntu

ansible-playbook -i hosts__primary_cluster.yml \
  playbook-primary-cluster.yml \
  --vault-password-file=vault-pass
```

### What the playbook does (in order)

1. Validates OS and Ansible version
2. Installs system packages (`python3`, `gcc`, `jq`, `curl`, `ufw`, etc.)
3. Configures `/etc/hosts` entries across nodes
4. Installs and configures **Consul** client agent (joins `pg-consul-rhel`)
5. Installs **PostgreSQL 17** and extensions
6. Installs **Patroni** and writes `/etc/patroni/patroni.yml`
7. Installs **pgBackRest**, writes `/etc/pgbackrest/pgbackrest.conf`
8. Mounts the **SMB share** (`mfsymlinks,guest,...`) and persists in `/etc/fstab`
9. Bootstraps the cluster (`initdb` on the first node, replicas stream from it)
10. Runs `pgbackrest stanza-create` on the primary
11. Configures `ufw` firewall rules (ports 5432, 8008, 8300–8600)
12. Sets up `postgres_exporter` on port `9194`

### Verify after setup

```bash
# Cluster state
ansible pg-cls1-prod1 -i hosts__primary_cluster.yml -u ansible -b \
  -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# pgBackRest stanza
ansible pg-cls1-prod1 -i hosts__primary_cluster.yml -u ansible -b \
  -m shell -a "sudo -u postgres pgbackrest --stanza=pg-cls1 info"

# WAL archiving
ansible pg-cls1-prod1 -i hosts__primary_cluster.yml -u ansible -b \
  -m shell -a "sudo -u postgres pgbackrest --stanza=pg-cls1 check"
```

---

## 5. Setup — Standby Cluster (DC2)

The DC2 cluster is a **Patroni standby cluster** — all its nodes replicate from the DC1 primary. The standby leader (`pg-cls1-dr1`) streams directly from `pg-cls1-prod1`; the other two DR nodes cascade from `pg-cls1-dr1`.

### Run the playbook

```bash
ansible-playbook -i hosts__standby_cluster.yml \
  playbook-standby-cluster.yml \
  --vault-password-file=vault-pass
```

### Key differences from primary cluster

| Aspect | Primary (DC1) | Standby (DC2) |
|--------|---------------|---------------|
| Patroni scope | `pg-cls1-prod` | `pg-cls1-dr` |
| `standby_cluster` in DCS | not set | `host: pg-cls1-prod1, port: 5432` |
| PostgreSQL role | read-write | read-only (always in recovery) |
| WAL source | archive-push to SMB | archive-get from SMB |
| SMB server IP | `192.168.100.1` | `192.168.200.1` |

### Verify after setup

```bash
# Standby cluster state — all nodes should show streaming
ansible pg-cls1-dr1 -i hosts__standby_cluster.yml -u ansible -b \
  -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# Confirm standby_cluster config in DCS
ansible pg-cls1-dr1 -i hosts__standby_cluster.yml -u ansible -b \
  -m shell -a "patronictl -c /etc/patroni/patroni.yml show-config"
```

### Reinitialise a stuck replica

```bash
# If a DR node is stuck in 'starting' after reinit
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml reinit pg-cls1-dr pg-cls1-dr2 --force"
```

---

## 6. Switchover & Failover

### 6.1 Planned Switchover (DC1 → DC2)

Use this when DC1 needs maintenance and DC2 should take over gracefully.

**Step 1 — Promote DC2 standby cluster to primary**
```bash
# Remove standby_cluster config from DC2 — this promotes it
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml edit-config \
      --set standby_cluster=null --force"
```

**Step 2 — Confirm DC2 is now primary**
```bash
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml list"
# Expect: dr1 shows 'Leader running', dr0/dr2 show 'Replica streaming'
# Expect: pg_is_in_recovery() = f on dr1
```

**Step 3 — Demote DC1 to new standby cluster**
```bash
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml edit-config \
      --set standby_cluster='{host: pg-cls1-dr1, port: 5432}' --force"
```

**Step 4 — Reinitialise DC1 replicas if stuck in archive recovery**
```bash
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml reinit pg-cls1-prod pg-cls1-prod0 --force"
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml reinit pg-cls1-prod pg-cls1-prod2 --force"
```

**Run via Ansible playbook**
```bash
ansible-playbook -i hosts__multi_datacenter.yml \
  playbook-multi-dc-failover.yml \
  --vault-password-file=vault-pass
```

---

### 6.2 Disaster Recovery — DC1 goes offline

When all DC1 nodes become unreachable and DC2 must become the new primary.

```
Before:  DC1 (pg-cls1-prod) = Primary TL N
         DC2 (pg-cls1-dr)   = Standby TL N

After:   DC1 = offline
         DC2 (pg-cls1-dr)   = Primary TL N+1
```

**Step 1 — Promote DC2**
```bash
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml edit-config \
      --set standby_cluster=null --force"
```

**Step 2 — Verify DC2 is writable**
```bash
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres psql -c 'SELECT pg_is_in_recovery(), current_timestamp;'"
# Expect: f | <timestamp>
```

---

### 6.3 Restoring DC1 as New Standby after DR

When DC1 comes back online after a DR event (risk of split-brain if both clusters think they are primary).

```
After DR promotion:
  DC2 (new primary) = TL N+1
  DC1 (came back)   = TL N or N+2  ← SPLIT BRAIN RISK
```

**Step 1 — Force a new leader election on DC2 to advance its timeline**
```bash
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml failover pg-cls1-dr \
      --candidate pg-cls1-dr1 --force"
# DC2 is now on TL N+2
```

**Step 2 — Convert DC1 into a standby cluster pointing at DC2**
```bash
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml edit-config \
      --set standby_cluster='{host: pg-cls1-dr1, port: 5432}' --force"
# DC1 leader rewinds to TL N+2 and starts streaming from DC2
```

**Step 3 — Reinitialise the other DC1 members**
```bash
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml reinit pg-cls1-prod pg-cls1-prod0 --force"
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml reinit pg-cls1-prod pg-cls1-prod1 --force"
```

---

## 7. Backup & Restore with pgBackRest

### Take a backup (run as `postgres` on the primary)

```bash
# Full backup
pgbackrest --stanza=pg-cls1 --type=full backup

# Differential backup
pgbackrest --stanza=pg-cls1 --type=diff backup

# List all backups
pgbackrest --stanza=pg-cls1 info

# Verify WAL archiving is healthy
pgbackrest --stanza=pg-cls1 check
```

### Via Ansible (from control node)

```bash
cd ~/GitHub/PostgreSQL-Learning/playbook-install-pg-cluster-ubuntu

ansible pg-cls1-prod1 -i hosts__multi_datacenter.yml -u ansible -b \
  -m shell -a "sudo -u postgres pgbackrest --stanza=pg-cls1 --type=full backup"
```

### Switch between SMB and S3 repositories

Edit `primary_cluster/defaults/main.yml` (and `standby_cluster/defaults/main.yml`):

```yaml
# Active — SMB share
pgbackrest_repo1_type: posix
pgbackrest_repo1_path: /stale-storage/share-stalestorage/pgbackrest_backups

# Inactive — S3 (uncomment to switch back)
#pgbackrest_repo1_type: s3
#pgbackrest_repo1_s3_endpoint: "..."
#pgbackrest_repo1_s3_bucket: "pg-db-backup"
#pgbackrest_repo1_s3_path: "/pg-backups"
```

Then re-run `playbook-update-pgbackrest-smb.yml` to push config to all nodes:
```bash
ansible-playbook -i hosts__multi_datacenter.yml \
  playbook-update-pgbackrest-smb.yml \
  --vault-password-file=vault-pass
```

---

## 8. Consul UI

Consul provides the DCS backend for Patroni and a web UI for cluster visibility.

**URL:** `http://pg-consul-rhel:8500/ui/dc1/services`

![Consul Services UI](consul-services-screenshot.png)

The Services page shows 4 registered services:

| Service | Instances | Tags | Meaning |
|---------|-----------|------|---------|
| `consul` | 1 | — | Consul server itself |
| `postgresql-16-main` | 1 | `db, primary` | Standalone PG instance on consul node |
| `pg-cls1-dr` | 3 | `replica, standby-leader` | DC2 standby cluster nodes |
| `pg-cls1-prod` | 3 | `master, primary, replica` | DC1 primary cluster nodes |

The `master` and `primary` tags on `pg-cls1-prod` indicate the current PostgreSQL primary. A health check failure on any node turns its service indicator red.

**Patroni DCS keys** (browse under Key/Value → `service/`):
```
service/pg-cls1-prod/leader      → pg-cls1-prod1
service/pg-cls1-prod/config      → dynamic cluster config (JSON)
service/pg-cls1-dr/leader        → pg-cls1-dr1
service/pg-cls1-dr/config        → standby_cluster config (JSON)
```

---

## 9. Troubleshooting

All commands assume:
```bash
cd ~/GitHub/PostgreSQL-Learning/playbook-install-pg-cluster-ubuntu
```

### Cluster health

```bash
# View full cluster state (both DCs)
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml list"
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml list"

# Check replication lag on all nodes
ansible all -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres psql -c 'SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn();'"

# Check Patroni REST API on each node
ansible all -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "curl -s http://localhost:8008/ | python3 -m json.tool | grep -E 'role|state|timeline'"
```

### Service management

```bash
# Restart Patroni on all prod nodes
ansible pg-cls1-prod0,pg-cls1-prod1,pg-cls1-prod2 \
  -i hosts__multi_datacenter.yml -u ansible -b \
  -m shell -a "systemctl restart patroni"

# Restart Consul on all prod nodes
ansible pg-cls1-prod0,pg-cls1-prod1,pg-cls1-prod2 \
  -i hosts__multi_datacenter.yml -u ansible -b \
  -m shell -a "systemctl restart consul"

# Check service status
ansible all -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "systemctl is-active patroni consul"
```

### Patroni operations

```bash
# Manual switchover within DC1 (change leader to prod0)
ansible pg-cls1-prod1 -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml switchover pg-cls1-prod \
      --master pg-cls1-prod1 --candidate pg-cls1-prod0 --force"

# Reinitialise a replica from scratch
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml reinit pg-cls1-prod pg-cls1-prod2 --force"

# Pause/resume Patroni auto-failover
ansible pg-cls1-prod1 -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml pause"
ansible pg-cls1-prod1 -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml resume"

# View/edit dynamic DCS config
ansible pg-cls1-prod1 -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "patronictl -c /etc/patroni/patroni.yml show-config"
```

### pgBackRest

```bash
# Check archiving health
ansible pg-cls1-prod1 -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres pgbackrest --stanza=pg-cls1 check"

# List backups
ansible pg-cls1-prod1 -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres pgbackrest --stanza=pg-cls1 info"

# Run full backup
ansible pg-cls1-prod1 -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres pgbackrest --stanza=pg-cls1 --type=full backup"

# Check pgbackrest async spool
ansible all -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "ls /var/spool/pgbackrest/"
```

### SMB share

```bash
# Verify mount on all nodes
ansible all -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "mountpoint /stale-storage/share-stalestorage && \
      mount | grep share-stalestorage | grep mfsymlinks"

# Remount if needed (reads from /etc/fstab)
ansible all -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "umount /stale-storage/share-stalestorage; \
      mount /stale-storage/share-stalestorage"

# Test write as postgres
ansible all -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres touch /stale-storage/share-stalestorage/.write_test && \
      sudo -u postgres rm /stale-storage/share-stalestorage/.write_test && \
      echo OK"
```

### Logs

```bash
# Patroni log (last 50 lines)
ansible pg-cls1-prod1 -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "journalctl -u patroni --no-pager -n 50"

# PostgreSQL startup log
ansible pg-cls1-prod2 -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres /usr/lib/postgresql/17/bin/pg_controldata \
      /var/lib/postgresql/17/main | grep -E 'state|checkpoint|timeline'"

# pg_controldata cluster state
ansible all -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres /usr/lib/postgresql/17/bin/pg_controldata \
      /var/lib/postgresql/17/main | grep 'cluster state'"
```

