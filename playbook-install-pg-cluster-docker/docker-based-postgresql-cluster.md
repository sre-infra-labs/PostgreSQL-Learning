# Docker-Based PostgreSQL 18 Cluster
## Patroni + etcd + pgbackrest + pgbouncer + pg_exporter

---

## Architecture

Each pg container runs all components — PostgreSQL, Patroni, **and etcd** — in a single container.
There is no separate etcd container. etcd forms a 3-member cluster across the 3 pg containers using
their Docker network IPs.

```
Host (macOS)
│
├── Docker Network: lab-network (172.18.0.0/16)  ← pre-existing shared network
│   │
│   ├── pg1  (172.18.0.11)  ← PostgreSQL 18 + Patroni + etcd (initial leader)
│   ├── pg2  (172.18.0.12)  ← PostgreSQL 18 + Patroni + etcd (replica)
│   ├── pg3  (172.18.0.13)  ← PostgreSQL 18 + Patroni + etcd (replica)
│   └── pg-bouncer (172.18.0.20) ← pgBouncer leader-routing proxy
│
└── Docker Named Volume: pg-backups  (shared pgbackrest POSIX repo)

Port Mapping  (host → container)
┌──────────┬────────┬────────┬────────────┬──────────────┬────────────┐
│ Container│ SSH    │ PG     │ Patroni    │ pg_exporter  │ pgBouncer  │
├──────────┼────────┼────────┼────────────┼──────────────┼────────────┤
│ pg1      │ 2221   │ 5433   │ 8011       │ 9194         │ 6433       │
│ pg2      │ 2222   │ 5434   │ 8012       │ 9195         │ 6434       │
│ pg3      │ 2223   │ 5435   │ 8013       │ 9196         │ 6435       │
│ pg-bouncer│ 2224  │ —      │ —          │ —            │ 5436       │
└──────────┴────────┴────────┴────────────┴──────────────┴────────────┘

etcd cluster (inter-container, no host port mapping needed):
  pg1: 172.18.0.11:2379 (client) / :2380 (peer)
  pg2: 172.18.0.12:2379 (client) / :2380 (peer)
  pg3: 172.18.0.13:2379 (client) / :2380 (peer)
```

---

## Component Stack

| Component          | Version   | Role                                            |
|--------------------|-----------|-------------------------------------------------|
| PostgreSQL         | 18 (PGDG) | Database engine                                 |
| Patroni            | 4.0.6     | HADR orchestration (automatic failover)         |
| etcd               | 3.5.17    | DCS — distributed configuration store          |
| pgbackrest         | latest    | Backup & restore (POSIX local shared volume)    |
| pgbouncer          | latest    | Connection pooler + leader-routing proxy        |
| pg_exporter        | 0.17.1    | Prometheus metrics (scraped by your local Prom) |
| pg_wait_sampling   | latest    | Wait event profiling (PGDG package)             |
| pg_wait_tracer     | main      | Wait event tracing (compiled from source)       |

### PostgreSQL Extensions Installed

From PGDG apt repo:
- `pg_stat_statements`, `pg_cron`, `pg_partman`, `pg_repack`
- `pgtap`, `plpgsql_check`, `pg_permissions`, `pg_qualstats`
- `pg_wait_sampling` (shared_preload_libraries)

From source:
- `pg_wait_tracer` (github.com/agroal/pg_wait_tracer)

---

## Project Layout

```
playbook-install-pg-cluster-docker/
├── Dockerfile                          # Ubuntu 24.04 + systemd + SSH base image
├── site.yml                            # Master: runs Phase 1 then Phase 2
├── playbook-setup-docker.yml           # Phase 1 — Docker infrastructure (localhost)
├── playbook-install-pg-cluster.yml     # Phase 2 — PG cluster install (containers)
├── hosts.yml                           # Ansible inventory
├── sensitive-values                    # Ansible-vault encrypted credentials  ← DO NOT COMMIT
├── sensitive-values-sample             # Sample credentials file              ← commit this
├── vault-pass                          # Vault password file                  ← DO NOT COMMIT
├── vars/
│   └── dba_vars.yml                    # DBA input variables
└── roles/
    ├── docker_infrastructure/          # Phase 1 role
    │   ├── defaults/main.yml
    │   └── tasks/
    │       ├── main.yml
    │       └── custom/
    │           ├── network.yml         # Create Docker network
    │           ├── build_image.yml     # Build pg-cluster-node image
    │           ├── pg_containers.yml   # Create pg1/pg2/pg3 + pg-bouncer containers
    │           └── pgbouncer_container.yml
    └── pg_cluster/                     # Phase 2 role (runs inside containers)
        ├── defaults/
        │   ├── main.yml               # All PG / Patroni / etcd parameters
        │   ├── dba_vars.yml
        │   └── creds.yml
        ├── handlers/main.yml
        ├── tasks/
        │   ├── main.yml
        │   └── custom/
        │       ├── prechecks.yml      # Pre-flight checks + reinit cleanup
        │       ├── repository.yml     # Add PGDG apt repo
        │       ├── packages.yml       # PG18 + extensions + patroni + pg_wait_tracer
        │       ├── etcd.yml           # Install etcd binary + systemd service
        │       ├── patroni.yml        # Patroni config + start (leader first → replicas)
        │       ├── pgbackrest.yml     # pgbackrest config + stanza-create
        │       ├── pgbouncer.yml      # pgbouncer + Patroni callback script
        │       ├── pg_exporter.yml    # Prometheus postgres_exporter
        │       ├── user.yml           # DB users + extensions
        │       ├── pgpass.yml         # .pgpass file
        │       └── patronictl_list.yml
        └── templates/
            ├── patroni.yml.j2         # Patroni config (etcd3 DCS, dynamic hosts)
            ├── etcd.env.j2            # etcd environment file
            ├── etcd.service.j2        # etcd systemd unit
            ├── pgbackrest.conf.j2     # pgbackrest (POSIX local repo)
            └── pgbouncer.ini.j2       # pgbouncer config
```

---

## Prerequisites

### 1. Install Ansible

```bash
brew install ansible
ansible --version   # should show core 2.18+
```

### 2. Install required Ansible collections

```bash
ansible-galaxy collection install community.docker community.postgresql
```

### 3. Ensure an SSH key exists

```bash
ls ~/.ssh/id_rsa.pub 2>/dev/null || ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

### 4. Docker Desktop must be running

```bash
docker info   # should succeed
```

---

## Setup

### Step 1 — Configure vault password

```bash
cd playbook-install-pg-cluster-docker/
echo 'YourVaultPassword' > vault-pass
chmod 600 vault-pass
```

### Step 2 — Configure credentials

The `sensitive-values` file is already encrypted with vault. To change passwords:

```bash
ansible-vault edit sensitive-values --vault-password-file=vault-pass
```

Contents of `sensitive-values` (edit with vault, never put real passwords in docs):
```yaml
PG_SUPERUSER_PWD:      <your-pg-superuser-password>
DB_USER_RW_PASSWORD:   <your-rw-user-password>
DB_USER_RO_PASSWORD:   <your-ro-user-password>
PGBACKREST_REPO1_PATH: /var/lib/pgbackrest
```

### Step 3 — Review DBA variables

Edit `vars/dba_vars.yml` to adjust cluster name, PG version, hardware resources, and network name:

```yaml
patroni_cluster_name: "pg-docker-cls1"
postgresql_version: "18"
docker_network_name: "lab-network"      # pre-existing shared Docker network
etcd_version: "3.5.17"
```

### Step 4 — Run Phase 1: Docker Infrastructure

```bash
ansible-playbook playbook-setup-docker.yml    # no vault needed — no credentials used here
```

What this does:
- Verifies Docker network `lab-network` exists (never creates it — it's a shared network)
- Builds `pg-cluster-node:latest` image from `Dockerfile`
- Creates containers: `pg1`, `pg2`, `pg3` (Ubuntu 24.04 + systemd + SSH)
- Creates container: `pg-bouncer` (pgBouncer leader-routing proxy)
- Creates Docker named volumes: `pg-data-pg{1,2,3}`, `pg-logs-pg{1,2,3}`, `pg-backups`
- Injects your SSH public key into all containers

### Step 5 — Run Phase 2: Install PostgreSQL Cluster

```bash
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml --vault-password-file=vault-pass
```

What this does (on all 3 containers):
1. Pre-flight checks (etcd connectivity, no existing cluster data)
2. Add PGDG apt repository
3. Install PostgreSQL 18 + all extensions + Patroni + pgBouncer
4. Compile and install `pg_wait_tracer` from source
5. Install etcd binary + configure 3-member systemd service
6. Configure and start Patroni (leader initializes → replicas stream)
7. Configure pgbackrest (POSIX local repo on shared `pg-backups` volume)
8. Configure pgBouncer + Patroni callback for automatic leader routing
9. Install and start `postgres_exporter` (port 9194)
10. Create application database + users + extensions

### Step 6 — Verify

```bash
# Patroni cluster state
docker exec -u postgres pg1 patronictl -c /etc/patroni/patroni.yml list

# etcd cluster members
docker exec pg1 etcdctl --endpoints=http://172.18.0.11:2379 member list

# Connect directly to each node
psql -h 127.0.0.1 -p 5433 -U postgres postgres   # pg1
psql -h 127.0.0.1 -p 5434 -U postgres postgres   # pg2
psql -h 127.0.0.1 -p 5435 -U postgres postgres   # pg3

# Connect via pgBouncer (always routes to current leader)
psql -h 127.0.0.1 -p 5436 -U postgres postgres

# Check pg_exporter
curl -s http://localhost:9194/metrics | grep pg_up
curl -s http://localhost:9195/metrics | grep pg_up
curl -s http://localhost:9196/metrics | grep pg_up

# etcd health on each node
curl -s http://127.0.0.1:2379/health   # (from inside container via docker exec)
docker exec pg1 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 endpoint health
```

---

## Prometheus Scrape Config

Add to your existing `prometheus.yml` on your Mac:

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
```

Reload Prometheus after editing:
```bash
curl -X POST http://localhost:9090/-/reload
```

---

## Common Operations

```bash
# Run a specific tag/component only
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags etcd
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags patroni
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags pgbouncer

# Reinitialize cluster (DESTROYS ALL DATA)
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true

# Reinitialize + clean pgbackrest backups
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true -e cleanup_pgbackrest_backups=true

# SSH into containers
ssh -i ~/.ssh/id_rsa -p 2221 -o StrictHostKeyChecking=no ansible@127.0.0.1   # pg1
ssh -i ~/.ssh/id_rsa -p 2222 -o StrictHostKeyChecking=no ansible@127.0.0.1   # pg2
ssh -i ~/.ssh/id_rsa -p 2223 -o StrictHostKeyChecking=no ansible@127.0.0.1   # pg3

# Stop / restart all containers
docker stop pg1 pg2 pg3 pg-bouncer
docker start pg1 pg2 pg3 pg-bouncer

# Full teardown — WARNING: destroys all data
docker rm -f pg1 pg2 pg3 pg-bouncer
docker volume rm pg-data-pg1 pg-data-pg2 pg-data-pg3 \
                 pg-logs-pg1 pg-logs-pg2 pg-logs-pg3 pg-backups

# Check Patroni REST API directly
curl -s http://127.0.0.1:8011/patroni | python3 -m json.tool   # pg1
curl -s http://127.0.0.1:8011/primary   # 200 if pg1 is leader, 503 otherwise

# Trigger manual failover
docker exec -u postgres pg1 \
  patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --master pg1 --force
```

---

## Manual pgbackrest Backup & Restore

```bash
# Full backup (run on leader)
docker exec -u postgres pg1 \
  pgbackrest --stanza=pg-docker-cls1 --log-level-console=info backup --type=full

# Differential backup
docker exec -u postgres pg1 \
  pgbackrest --stanza=pg-docker-cls1 --log-level-console=info backup --type=diff

# List backups
docker exec -u postgres pg1 \
  pgbackrest --stanza=pg-docker-cls1 info

# Point-in-time restore (stop patroni first)
docker exec pg1 systemctl stop patroni
docker exec -u postgres pg1 \
  pgbackrest --stanza=pg-docker-cls1 --log-level-console=info restore --delta \
  --target="2025-01-15 10:30:00" --target-action=promote
docker exec pg1 systemctl start patroni
```

---

## Firewall

Docker Desktop manages port exposure via the `ports:` mapping defined in
`roles/docker_infrastructure/defaults/main.yml`. All inter-container traffic
(including etcd peer communication on port 2380) flows on the `lab-network`
internal Docker bridge network and does not need host-level firewall rules.

Ports exposed to the host (macOS firewall may need to allow these if you enable
the macOS application firewall):
- `2221–2223` — SSH
- `5433–5435` — PostgreSQL
- `5436`       — pgBouncer leader endpoint
- `6433–6435` — pgBouncer per-node
- `8011–8013` — Patroni REST API
- `9194–9196` — pg_exporter (Prometheus scrape)

---

## Notes

- **etcd inside containers**: each pg container runs an etcd member. The 3-member
  cluster tolerates 1 node failure. etcd data lives at `/var/lib/etcd` inside each
  container (survives `docker stop/start`, lost on `docker rm`).

- **pgbackrest POSIX repo**: all containers share the `pg-backups` Docker named volume
  mounted at `/var/lib/pgbackrest`. This simulates shared NFS storage.

- **pgBouncer callback**: Patroni calls `/usr/local/bin/patroni_pgbouncer_callback.sh`
  on role-change. The script polls all nodes' Patroni REST API to find the new leader
  and updates `/etc/pgbouncer/pgbouncer.ini`, then reloads pgBouncer.

- **pg_wait_tracer**: built from source ([agroal/pg_wait_tracer](https://github.com/agroal/pg_wait_tracer)).
  Build may fail if the extension has not been updated for PG18 — the playbook warns
  and continues without failing the run.

- **Passwords**: credentials are stored in the vault-encrypted `sensitive-values` file.
  Edit with: `ansible-vault edit sensitive-values --vault-password-file=vault-pass`
