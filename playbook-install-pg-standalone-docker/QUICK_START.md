# Quick Start Guide

## TL;DR (60 seconds)

```bash
cd playbook-install-pg-standalone-docker/

# 1. Create Docker network (one-time)
docker network create --driver bridge --subnet=172.19.0.0/16 lab-network

# 2. Setup secrets
cp sensitive-values-sample sensitive-values
vi sensitive-values
ansible-vault encrypt sensitive-values --vault-password-file=vault-pass

# 3. Run installation
ansible-playbook site.yml --vault-password-file=vault-pass

or

ANSIBLE_LOG_PATH="logs/playbook-setup-docker---$(date '+%Y-%m-%d__%H_%M_%S').log" \
ansible-playbook playbook-setup-docker.yml --vault-password-file=vault-pass

ANSIBLE_LOG_PATH="logs/playbook-install-pg-standalone---$(date '+%Y-%m-%d__%H_%M_%S').log" \
ansible-playbook playbook-install-pg-standalone.yml --vault-password-file=vault-pass

# 4. Access PostgreSQL
docker exec docpg-standalone psql -U postgres -c "SELECT version();"
```

## Prerequisites

- Docker installed and running
- Ansible 2.18+
- macOS, Linux, or WSL2 environment
- Internet access (for package downloads)

## Step-by-Step Setup

### 1. Create Docker Network

This is a **one-time setup** for your lab environment.

```bash
docker network create --driver bridge --subnet=172.19.0.0/16 lab-network
```

Verify:
```bash
docker network inspect lab-network
```

### 2. Prepare Secrets

```bash
cd playbook-install-pg-standalone-docker/

# Copy the sample file
cp sensitive-values-sample sensitive-values

# Edit with your passwords
vi sensitive-values
```

Update these lines in `sensitive-values`:
```yaml
PG_SUPERUSER_PWD: "YourSecurePassword123!"
DB_USER_RW_PASSWORD: "RWUserPassword456"
DB_USER_RO_PASSWORD: "ROUserPassword789"
```

**Encrypt the file:**
```bash
ansible-vault encrypt sensitive-values --vault-password-file=vault-pass
```

> **Note:** The `vault-pass` file is the encryption key. Change it from the default for production use.

### 3. (Optional) Customize Configuration

Edit these files to customize your setup:

#### `hosts.yml` — Container IP and Network
```yaml
docpg-standalone:
  ip: "172.19.0.11"        # Container IP (must be in the network subnet)

docker_network: lab-network
docker_network_subnet: "172.19.0.0/16"
```

#### `vars/dba_vars.yml` — PostgreSQL Settings
```yaml
postgresql_version: "18"
postgresql_port: "5432"
db_name: "dba"
db_user_rw: dba_rw
db_user_ro: dba_ro
pgbouncer_listen_port: 6432
pgbouncer_pool_mode: "transaction"
```

### 4. Run the Installation

**Full installation (recommended):**
```bash
ansible-playbook site.yml --vault-password-file=vault-pass
```

**Or run phases separately:**
```bash
# Phase 1: Docker setup (network, image, container)
ansible-playbook playbook-setup-docker.yml

# Phase 2: PostgreSQL installation
ansible-playbook -i hosts.yml playbook-install-pg-standalone.yml --vault-password-file=vault-pass
```

## Access PostgreSQL

### From Mac Host

```bash
# Direct psql access
docker exec docpg-standalone psql -U postgres -c "SELECT version();"

# Interactive shell
docker exec -it docpg-standalone psql -U postgres

# Via pgBouncer (connection pooler)
docker exec docpg-standalone psql -h 127.0.0.1 -p 6432 -U dba_rw -d dba
```

### Inside Container

```bash
# Enter the container shell
docker exec -it docpg-standalone bash

# Switch to postgres user
su - postgres

# Connect to PostgreSQL
psql
```

## Common Tasks

### Check PostgreSQL Status

```bash
docker exec docpg-standalone systemctl status postgresql
docker exec docpg-standalone journalctl -u postgresql -n 20
```

### Check pgBouncer Status

```bash
docker exec docpg-standalone systemctl status pgbouncer
docker exec docpg-standalone tail -f /var/log/pgbouncer/pgbouncer.log
```

### View PostgreSQL Logs

```bash
docker exec docpg-standalone tail -f /var/log/postgresql/postgresql-*.log
```

### Create a Database

```bash
docker exec docpg-standalone psql -U postgres -c "CREATE DATABASE mydb;"
docker exec docpg-standalone psql -U postgres -l
```

### Backup Database

```bash
docker exec docpg-standalone pgbackrest backup
docker exec docpg-standalone pgbackrest info
```

### Full Cleanup (Fresh Install)

```bash
# Stop and remove container and volumes
ansible-playbook playbook-cleanup.yml

# Then re-run installation
ansible-playbook site.yml --vault-password-file=vault-pass
```

### Reinitialize PostgreSQL (Keep Container)

```bash
# Clean and reinstall PostgreSQL only
ansible-playbook -i hosts.yml playbook-install-pg-standalone.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true
```

## What Gets Installed

| Component | Version | Purpose |
|-----------|---------|---------|
| PostgreSQL | 18 (configurable) | Database |
| pgBackRest | Latest | Backup & WAL archiving |
| pg_stat_statements | Built-in | Query statistics |
| pg_cron | Built-in | Scheduled jobs |

## Services Running in Container

| Service | Port | Access |
|---------|------|--------|
| PostgreSQL | 5432 | Via `docker exec` |
| systemd | — | For service management |

## Directory Structure Quick Reference

```
playbook-install-pg-standalone-docker/
├── README.md                  # Full documentation
├── QUICK_START.md             # This file
├── STRUCTURE.md               # Directory and file reference
├── hosts.yml                  # Inventory (container IP, network)
├── vars/dba_vars.yml          # PostgreSQL configuration
├── site.yml                   # Master playbook
├── playbook-setup-docker.yml  # Phase 1
├── playbook-install-pg-standalone.yml  # Phase 2
├── playbook-cleanup.yml       # Cleanup
├── Dockerfile                 # Container image
└── roles/
    ├── docker_infrastructure/ # Docker tasks
    └── pg_standalone/         # PostgreSQL tasks
```

See `STRUCTURE.md` for detailed documentation.

## Troubleshooting

### Container won't start

```bash
# Check logs
docker logs docpg-standalone

# Check if port 5432 is already in use
docker ps
netstat -an | grep 5432

# Verify network exists
docker network ls
```

### PostgreSQL won't start

```bash
docker exec docpg-standalone journalctl -u postgresql -n 50
docker exec docpg-standalone ls -la /var/lib/postgresql/18/main/
```

### Permission denied errors

```bash
# Make sure vault password file has correct permissions
chmod 600 vault-pass sensitive-values
```

### ansible: command not found

Install Ansible:
```bash
pip install ansible
```

### Docker daemon not running

Start Docker Desktop and wait for it to be ready.

## Getting Help

1. **Check logs:**
   ```bash
   docker logs docpg-standalone
   docker exec docpg-standalone journalctl -xe
   ```

2. **Run with verbose output:**
   ```bash
   ansible-playbook site.yml --vault-password-file=vault-pass -vvv
   ```

3. **Read the documentation:**
   - `README.md` — Full setup and troubleshooting guide
   - `STRUCTURE.md` — File and directory reference

## Next Steps

After successful installation:

1. **Create application databases** — Use PostgreSQL roles and databases
2. **Setup backups** — Configure pgBackRest backup schedule
3. **Monitor** — Expose pg_exporter metrics to Prometheus/Grafana
4. **Performance tune** — Adjust `vars/dba_vars.yml` parameters
5. **Learn** — Study PostgreSQL, pgBouncer, and pgBackRest documentation

---

**Questions?** Check README.md for detailed documentation and troubleshooting.
