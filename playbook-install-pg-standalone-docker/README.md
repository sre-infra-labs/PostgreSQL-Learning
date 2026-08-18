# Docker-Based PostgreSQL 18 Standalone

A simplified Ansible playbook for installing a **standalone PostgreSQL** database in a Docker container with pgBackRest.

## Quick Overview

This playbook:
- **Creates a Docker container** named `docpg-standalone` on a custom `lab-network`
- **Installs PostgreSQL 18** with pg_stat_statements and pg_cron extensions
- **Configures pgBackRest** for backups and WAL archiving
- **Creates application users** (dba_rw, dba_ro) and a database named 'dba'

## Structure

Similar to the cluster playbook but simplified:
- **hosts.yml** — Inventory with a single 'standalone' group containing one PostgreSQL node
- **site.yml** — Master playbook orchestrating Phase 1 (Docker) and Phase 2 (PostgreSQL)
- **playbook-setup-docker.yml** — Phase 1: Create Docker network, image, and containers
- **playbook-install-pg-standalone.yml** — Phase 2: Install and configure PostgreSQL
- **playbook-cleanup.yml** — Tear down containers and network
- **roles/docker_infrastructure** — Simplified Docker setup for standalone
- **roles/pg_standalone** — PostgreSQL installation and configuration

## Configuration

### 1. Customize hosts.yml

Edit container name, IP address, and network settings:

```yaml
all:
  children:
    standalone:
      hosts:
        docpg-standalone:
          ip: "172.19.0.11"   # Adjust as needed

  vars:
    docker_network: lab-network
    docker_network_subnet: "172.19.0.0/16"
```

### 2. Customize vars/dba_vars.yml

Adjust PostgreSQL version, port, hardware allocation, database names, and users:

```yaml
postgresql_version: "18"
postgresql_port: "5432"
db_name: "dba"
db_user_rw: dba_rw
db_user_ro: dba_ro
pgbouncer_listen_port: 6432
```

### 3. Setup Secrets (sensitive-values)

```bash
# Start from the sample
cp sensitive-values-sample sensitive-values

# Edit with your actual passwords
vi sensitive-values

# Encrypt with Ansible Vault
ansible-vault encrypt sensitive-values --vault-password-file=vault-pass
```

The `vault-pass` file contains the vault password. Change it for production.

## Setup Instructions

### Phase 1: Create Docker Network

```bash
cd playbook-install-pg-standalone-docker/

# Create the Docker network (one-time setup)
docker network create --driver bridge --subnet=172.19.0.0/16 lab-network
```

### Phase 2: Run Full Installation

```bash
# Run both phases (Docker setup + PostgreSQL install)
ansible-playbook site.yml --vault-password-file=vault-pass

# Or run phases individually:

# Phase 1 only: Setup Docker infrastructure
ansible-playbook playbook-setup-docker.yml

# Phase 2 only: Install PostgreSQL
ansible-playbook -i hosts.yml playbook-install-pg-standalone.yml --vault-password-file=vault-pass
```

### Reinitialize (Fresh Install)

```bash
# Full cleanup (containers + volumes)
ansible-playbook playbook-cleanup.yml

# Then re-run Phase 1 + Phase 2
ansible-playbook site.yml --vault-password-file=vault-pass
```

## Services Inside Container

Access services via `docker exec <container_name>`:

| Service | Port | Notes |
|---------|------|-------|
| PostgreSQL | 5432 | Main database |

## Connect from Mac Host

```bash
# List running containers
docker ps --filter name=docpg-standalone

# Connect via docker exec
docker exec docpg-standalone psql -U postgres -c "SELECT version();"

# Or use the .pgpass file for passwordless access
docker exec docpg-standalone psql -h 127.0.0.1 -U dba_rw dba
```

## Configurable Parameters

### Container & Network
- `docker_network` — Docker network name (default: lab-network)
- `docker_network_subnet` — Network CIDR (default: 172.19.0.0/16)
- Container IP — Set via `hosts.yml`

### PostgreSQL
- `postgresql_version` — PG version from PGDG (default: 18)
- `postgresql_port` — PG listen port (default: 5432)
- `postgresql_locale` — Locale for initdb (default: en_US.UTF-8)
- `postgresql_data_checksums` — Enable checksums (default: true)

### Application
- `db_name` — Main application database (default: dba)
- `db_user_rw` — Read-write user (default: dba_rw)
- `db_user_ro` — Read-only user (default: dba_ro)

### pgBackRest
- `pgbackrest_repo1_path` — Backup repo path (default: /var/lib/pgbackrest)
- `pgbackrest_repo1_retention_full` — Full backup retention (default: 7)

## Cleanup

```bash
# Remove containers, volumes, but keep network and image
ansible-playbook playbook-cleanup.yml

# Manually clean up Docker network (if not shared with other containers)
docker network rm lab-network
```

## Tips

1. **Reuse the lab-network** — The `playbook-setup-docker.yml` requires the network to exist first.
   Use the same network for all lab containers (Postgres, MongoDB, etc.).

2. **Check container logs** — Review setup progress:
   ```bash
   docker exec docpg-standalone journalctl -u postgresql -f
   docker exec docpg-standalone tail -f /var/log/pgbouncer/pgbouncer.log
   docker exec docpg-standalone tail -f /var/log/postgresql/postgresql-*.log
   ```

3. **Reinitialize after failures** — Use `-e reinit_cluster=true`:
   ```bash
   ansible-playbook -i hosts.yml playbook-install-pg-standalone.yml \
     --vault-password-file=vault-pass -e reinit_cluster=true
   ```

4. **Run specific tasks** — Use Ansible tags:
   ```bash
   # PostgreSQL setup only
   ansible-playbook -i hosts.yml playbook-install-pg-standalone.yml \
     --vault-password-file=vault-pass --tags postgresql

   # pgBouncer configuration only
   ansible-playbook -i hosts.yml playbook-install-pg-standalone.yml \
     --vault-password-file=vault-pass --tags pgbouncer
   ```

## Troubleshooting

### Container won't start
```bash
docker logs docpg-standalone
docker inspect docpg-standalone
```

### PostgreSQL fails to initialize
```bash
docker exec docpg-standalone journalctl -u postgresql -n 100
docker exec docpg-standalone ls -la /var/lib/postgresql/18/main/
```

### Connectivity issues
```bash
# Test network access inside container
docker exec docpg-standalone ping 172.19.0.1
docker exec docpg-standalone curl -s http://127.0.0.1:9187/metrics | head
```

## Differences from Cluster Playbook

Unlike the **playbook-install-pg-cluster-docker-etcd**, the standalone version:

✅ **Simpler**
- Single node (no Patroni, no etcd, no replication)
- No HAProxy or Keepalived
- No cluster VIPs or failover

✅ **Smaller Network**
- Uses 172.19.0.0/16 instead of 172.18.0.0/16
- Single container IP needed

✅ **Streamlined Configuration**
- Fewer variables to configure
- Same variable structure for consistency
- Same Docker setup pattern for familiarity

Both playbooks follow the same Ansible role structure and use the same tools (pgBackRest, pgBouncer, pg_exporter) for learning and comparison.
