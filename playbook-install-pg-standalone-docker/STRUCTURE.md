# Playbook Structure

## Directory Layout

```
playbook-install-pg-standalone-docker/
├── README.md                          # Main documentation
├── STRUCTURE.md                       # This file
├── ansible.cfg                        # Ansible configuration
├── site.yml                           # Master playbook (orchestrates phases)
├── hosts.yml                          # Inventory: defines 'standalone' host group
│
├── Playbooks
├── playbook-setup-docker.yml          # Phase 1: Docker network, image, containers
├── playbook-install-pg-standalone.yml # Phase 2: PostgreSQL + extensions
├── playbook-cleanup.yml               # Teardown: Remove containers and volumes
│
├── Configuration
├── ansible.cfg                        # Ansible settings (inventory, plugins, etc.)
├── vault-pass                         # Ansible Vault password (for sensitive-values)
├── vars/
│   └── dba_vars.yml                   # DBA variables (PostgreSQL, pgBouncer, etc.)
│
├── Secrets
├── sensitive-values-sample            # Template for vault secrets
├── sensitive-values                   # ENCRYPTED vault file (git-ignored, create from sample)
│
├── Docker
├── Dockerfile                         # Container image definition (Ubuntu 24.04 + systemd)
│
├── Roles
├── roles/
│   ├── docker_infrastructure/         # Phase 1: Docker setup (network, image, containers)
│   │   ├── defaults/
│   │   │   └── main.yml               # Defaults: docker_network, image name, volumes
│   │   └── tasks/
│   │       ├── main.yml               # Orchestrates custom tasks
│   │       └── custom/
│   │           ├── network.yml        # Verify or create Docker network
│   │           ├── build_image.yml    # Build pg-standalone-node image from Dockerfile
│   │           └── pg_containers.yml  # Create standalone PostgreSQL container
│   │
│   └── pg_standalone/                 # Phase 2: PostgreSQL installation
│       ├── defaults/
│       │   ├── main.yml               # PostgreSQL defaults (version, paths, parameters)
│       │   └── creds.yml              # Maps vault secrets to 'creds' namespace
│       ├── handlers/
│       │   └── main.yml               # Event handlers (reload pgbouncer, restart services)
│       ├── tasks/
│       │   ├── main.yml               # Orchestrates custom tasks in order
│       │   └── custom/
│       │       ├── prechecks.yml      # Validate Ansible version, handle reinit cleanup
│       │       ├── repository.yml     # Setup PGDG apt repository
│       │       ├── packages.yml       # Install system + PostgreSQL packages
│       │       ├── container_env.yml  # Set PostgreSQL env vars (PATH, PGDATA, etc.)
│       │       ├── pgpass.yml         # Create .pgpass for passwordless auth
│       │       ├── postgresql.yml     # Initialize and start PostgreSQL
│       │       ├── pgbackrest.yml     # Configure pgBackRest, create stanza
│       │       ├── pgbouncer.yml      # Configure pgBouncer connection pooler
│       │       ├── pg_exporter.yml    # Install postgres_exporter for Prometheus
│       │       └── user.yml           # Create application database and users
│       └── templates/
│           ├── pgbackrest.conf.j2     # pgBackRest configuration template
│           └── pgbouncer.ini.j2       # pgBouncer configuration template
```

## File Purpose Reference

### Root Files

| File | Purpose |
|------|---------|
| `README.md` | Quick start, setup instructions, troubleshooting |
| `STRUCTURE.md` | This file — documentation of directory structure |
| `ansible.cfg` | Ansible settings: inventory, plugins, logging |
| `site.yml` | Master playbook that runs both Phase 1 and Phase 2 |
| `hosts.yml` | Inventory file; defines 'standalone' host group and network config |
| `vault-pass` | Password file for Ansible Vault (change for production) |
| `Dockerfile` | Container image definition (Ubuntu 24.04 with systemd) |

### Playbooks

| Playbook | Purpose |
|----------|---------|
| `playbook-setup-docker.yml` | Phase 1: Create Docker network, build image, launch container |
| `playbook-install-pg-standalone.yml` | Phase 2: Install PostgreSQL, extensions, pgBouncer, pgBackRest |
| `playbook-cleanup.yml` | Teardown: Stop and remove containers and volumes |

### Configuration

| File | Purpose |
|------|---------|
| `vars/dba_vars.yml` | PostgreSQL version, port, database names, users, hardware allocation |
| `sensitive-values-sample` | Template showing structure of vault secrets |
| `sensitive-values` | ENCRYPTED vault file (created from sample, git-ignored) |

### docker_infrastructure Role

Sets up Docker network, builds container image, creates standalone container.

| Task | Purpose |
|------|---------|
| `network.yml` | Verify Docker network exists (must be created manually on Mac) |
| `build_image.yml` | Build `pg-standalone-node:latest` image from Dockerfile |
| `pg_containers.yml` | Create Docker container, volumes, and attach to network |

### pg_standalone Role

Installs and configures PostgreSQL inside the container.

| Task | Purpose |
|------|---------|
| `prechecks.yml` | Ansible version check, reinit cleanup (if needed) |
| `repository.yml` | Setup PGDG apt repository for PostgreSQL packages |
| `packages.yml` | Install system packages and PostgreSQL |
| `container_env.yml` | Set PostgreSQL env vars in /etc/environment, .bashrc, etc. |
| `pgpass.yml` | Create .pgpass files for passwordless authentication |
| `postgresql.yml` | Initialize PostgreSQL data dir, start service, set superuser password |
| `pgbackrest.yml` | Configure pgBackRest, create stanza for backups |
| `user.yml` | Create application database and read-write/read-only users |

## Key Variables

### hosts.yml

```yaml
docker_network: lab-network              # Docker bridge network name
docker_network_subnet: 172.19.0.0/16     # Network CIDR
docpg-standalone:
  ip: 172.19.0.11                        # Container IP address (fixed)
```

### vars/dba_vars.yml

```yaml
postgresql_version: "18"                 # PostgreSQL major version from PGDG
postgresql_port: "5432"                  # PG listen port
db_name: "dba"                           # Application database
db_user_rw: dba_rw                       # Read-write user
db_user_ro: dba_ro                       # Read-only user
pgbouncer_listen_port: 6432              # Connection pooler port
pgbouncer_pool_mode: transaction         # Pool mode (transaction or session)
```

### sensitive-values (Vault)

```yaml
PG_SUPERUSER_PWD: "..."                  # PostgreSQL superuser password
DB_USER_RW_PASSWORD: "..."               # dba_rw user password
DB_USER_RO_PASSWORD: "..."               # dba_ro user password
PGBACKREST_REPO1_PATH: "/var/lib/pgbackrest"  # Backup repository path
```

## Comparison with Cluster Playbook

| Aspect | Cluster | Standalone |
|--------|---------|-----------|
| Nodes | 3+ nodes (primary + replicas) | 1 node |
| HA Manager | Patroni + etcd | None (standalone) |
| Replication | Yes (streaming) | No |
| Failover | Automatic (VIP) | Manual (restart) |
| Reverse Proxy | HAProxy + Keepalived | None |
| Network | 172.18.0.0/16 | 172.19.0.0/16 |
| Image | `pg-cluster-node:latest` | `pg-standalone-node:latest` |
| Containers | Multiple (pg1, pg2, pg3, ...) | Single (docpg-standalone) |
| Complexity | High (12+ custom tasks) | Medium (10 custom tasks) |

**Both** use the same tools (pgBackRest, pgBouncer, pg_exporter) and follow the same Ansible patterns.

## Usage Examples

```bash
cd playbook-install-pg-standalone-docker/

# Create Docker network (one-time setup)
docker network create --driver bridge --subnet=172.19.0.0/16 lab-network

# Run full installation (Phase 1 + Phase 2)
ansible-playbook site.yml --vault-password-file=vault-pass

# Or run phases individually
ansible-playbook playbook-setup-docker.yml
ansible-playbook -i hosts.yml playbook-install-pg-standalone.yml --vault-password-file=vault-pass

# Full cleanup
ansible-playbook playbook-cleanup.yml

# Reinitialize (fresh install)
ansible-playbook -i hosts.yml playbook-install-pg-standalone.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true

# Run specific task only
ansible-playbook -i hosts.yml playbook-install-pg-standalone.yml \
  --vault-password-file=vault-pass --tags postgresql
```

## Configuration Hierarchy

Variables are resolved in this order (highest precedence first):

1. Extra vars (`-e` on command line)
2. `hosts.yml` (host-specific vars)
3. `vars/dba_vars.yml` (playbook-level vars)
4. Role `defaults/` (role-specific defaults)

Example: `docker_network` is defined in `hosts.yml` and will override the fallback value in `roles/docker_infrastructure/defaults/main.yml`.
