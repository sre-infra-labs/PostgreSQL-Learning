# Debezium CDC Learning Infrastructure

A comprehensive, modular Ansible-based infrastructure for learning **Change Data Capture (CDC)** using **Debezium** and **Kafka** with PostgreSQL as the source database.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Quick Start](#quick-start)
5. [Configuration](#configuration)
6. [Deployment](#deployment)
7. [Validation & Testing](#validation--testing)
8. [Access Portals](#access-portals)
9. [Advanced Usage](#advanced-usage)
10. [Troubleshooting](#troubleshooting)
11. [Cleanup](#cleanup)

---

## Overview

This infrastructure provides a **complete, production-like CDC setup** for learning purposes. All components run as Docker containers on your local machine within a custom Docker network (`cdc-network`).

### Key Features

✅ **Fully Modular**: Deploy components individually or all together  
✅ **Secure**: Uses Ansible Vault for sensitive data (no hardcoded credentials)  
✅ **Configurable**: All settings in `vars/main.yml`  
✅ **Production-Ready**: Real Debezium, Kafka, PostgreSQL configs  
✅ **Learning-Focused**: Includes pgBadger for log analysis, Kafka UI for monitoring  
✅ **Documented**: This README + inline comments in all files  
✅ **Validated**: Includes validation scripts and health checks  

### Included Components

| Component | Version | Container | Port (localhost) |
|-----------|---------|-----------|------------------|
| Docker Network | - | cdc-network (172.20.0.0/16) | - |
| Zookeeper | 3.8.1 | zk-cdc | 2181 |
| Kafka (Confluent) | 3.7.0 | kafka-cdc | 29092 |
| PostgreSQL | 15-alpine | postgres-cdc | 5433 |
| Debezium Connect | 2.5.1 | debezium-connect | 8083 |
| pgAdmin 4 | 8.5 | pgadmin4-cdc | 5050 |
| Kafka UI | 0.7.1 | kafka-ui-cdc | 8080 |
| pgBadger | 12.4 | pgadmin4-cdc | 8888 |

---

## Prerequisites

### System Requirements

- **OS**: macOS, Linux (Windows with WSL2)
- **Docker**: 20.10+ (with Docker Compose)
- **Ansible**: 2.9+
- **Python**: 3.7+
- **RAM**: Minimum 8GB (recommended 16GB for smooth operation)
- **Disk**: 10GB free space
- **Network**: Stable internet (for initial Docker image pulls)

### Installation

```bash
# macOS (using Homebrew)
brew install docker ansible

# Linux (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y docker.io ansible python3

# Verify installations
docker --version
ansible --version
```

### Start Docker Daemon

```bash
# macOS
open -a Docker

# Linux
sudo systemctl start docker
sudo systemctl enable docker
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        cdc-network (172.20.0.0/16)                 │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐    │
│  │ Zookeeper    │  │ Kafka Broker │  │ PostgreSQL (CDC)     │    │
│  │ 172.20.0.2   │  │ 172.20.0.3   │  │ 172.20.0.4           │    │
│  │ :2181        │  │ :9092        │  │ :5432                │    │
│  └──────────────┘  └──────────────┘  │ wal_level=logical    │    │
│                                       │ Logical Replication  │    │
│  ┌──────────────────────────────┐    └──────────────────────┘    │
│  │ Debezium Connect             │                                │
│  │ 172.20.0.5:8083              │    ┌──────────────────────┐    │
│  │ PostgreSQL Connector Active  │    │ pgAdmin 4 + pgBadger │    │
│  │ Topics: postgres.public.*    │    │ 172.20.0.6:80        │    │
│  └──────────────────────────────┘    │ Admin Portal         │    │
│                                       │ Log Analysis         │    │
│  ┌──────────────────────────────┐    └──────────────────────┘    │
│  │ Kafka UI (Monitoring)        │                                │
│  │ 172.20.0.7:8080              │    pgBadger Reports:         │
│  │ View topics, partitions      │    http://localhost:8888      │
│  │ Monitor messages flow        │                                │
│  └──────────────────────────────┘                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

                          ↓ (Port Mappings)

localhost:2181   (Zookeeper)
localhost:29092  (Kafka)
localhost:5433   (PostgreSQL)
localhost:8083   (Debezium REST API)
localhost:5050   (pgAdmin)
localhost:8080   (Kafka UI)
localhost:8888   (pgBadger Web Portal)
```

---

## Quick Start

### 1. Clone/Navigate to Project

```bash
cd ~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka
```

### 2. Setup Vault & Credentials

```bash
# Copy and edit the sensitive values sample
cp sensitive-values-sample sensitive-values

# Edit with your desired passwords
vi sensitive-values
# OR
nano sensitive-values

# Example content:
# PG_SUPERUSER_PASSWORD: "YourSecurePassword123!"
# PG_REPLICATION_PASSWORD: "YourSecurePassword456!"
# PG_APP_USER_PASSWORD: "YourSecurePassword789!"
# PGADMIN_DEFAULT_EMAIL: "admin@cdc-learning.local"
# PGADMIN_DEFAULT_PASSWORD: "PgAdminPassword123!"

# Encrypt the file with Ansible Vault
ansible-vault encrypt sensitive-values --vault-password-file=vault-pass

# Verify encryption
cat sensitive-values  # Should show encrypted content
ansible-vault view sensitive-values --vault-password-file=vault-pass  # Should show plaintext
```

### 3. Deploy All Components (Full Stack)

```bash
# Full deployment
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass

# Expected time: 3-5 minutes (depending on internet speed for Docker image pulls)

# Expected output (end of playbook):
# ✓ Debezium CDC Infrastructure Deployed Successfully!
```

### 4. Validate Deployment

```bash
# Check all containers are running
docker ps | grep cdc

# Expected output:
# kafka-ui-cdc        (healthy)
# pgadmin4-cdc        (healthy)
# debezium-connect    (healthy)
# postgres-cdc        (healthy)
# kafka-cdc           (healthy)
# zk-cdc              (healthy)

# Run validation script (if available)
./scripts/validate-deployment.sh
```

### 5. Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| pgAdmin | http://localhost:5050 | admin@cdc-learning.local / PgAdminPassword123! |
| Kafka UI | http://localhost:8080 | No auth |
| Debezium REST API | http://localhost:8083 | No auth |
| PostgreSQL CLI | psql -h localhost -p 5433 -U postgres | postgres / YourSecurePassword123! |

---

## Configuration

All configuration is in **vars/main.yml**. Edit this file BEFORE deployment:

```yaml
# ============================================================================
# DOCKER NETWORK & INFRASTRUCTURE
# ============================================================================
docker_network_name: "cdc-network"
docker_network_subnet: "172.20.0.0/16"
docker_volumes_root: "{{ ansible_env.HOME }}/cdc-volumes"

# ============================================================================
# ZOOKEEPER CONFIGURATION
# ============================================================================
zk_version: "3.8.1"
zk_container_name: "zk-cdc"
zk_host_mapping_port: 2181  # Port on localhost

# ============================================================================
# KAFKA CONFIGURATION
# ============================================================================
kafka_version: "3.7.0"
kafka_host_mapping_port: 29092  # Port on localhost
kafka_topics:
  - name: "postgres.public.users"
    partitions: 1
    replication_factor: 1
  - name: "postgres.public.orders"
    partitions: 1
    replication_factor: 1

# ============================================================================
# POSTGRESQL SOURCE DATABASE (CDC Source)
# ============================================================================
pg_version: "15"
pg_host_mapping_port: 5433  # Port on localhost (avoid conflict)
pg_wal_level: "logical"     # CRITICAL for CDC!
pg_max_wal_senders: 10
pg_wal_keep_size: "1GB"
pg_database: "cdc_db"
pg_replication_user: "replication"

# ============================================================================
# DEBEZIUM CONNECTOR
# ============================================================================
debezium_version: "2.5.1"
debezium_connector_name: "postgres-cdc-connector"
debezium_host_mapping_port: 8083

# ============================================================================
# PGADMIN & PGBADGER
# ============================================================================
pgadmin_host_mapping_port: 5050
pgbadger_version: "12.4"
pgbadger_enable: true

# ============================================================================
# KAFKA UI
# ============================================================================
kafka_ui_version: "0.7.1"
kafka_ui_host_mapping_port: 8080

# ============================================================================
# DEPLOYMENT OPTIONS
# ============================================================================
deploy_docker_infra: true
deploy_zookeeper: true
deploy_kafka: true
deploy_postgres: true
deploy_debezium: true
deploy_pgadmin: true
deploy_kafka_ui: true
deploy_pgbadger: true
```

---

## Deployment

### Option 1: Full Stack (All Components at Once)

```bash
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass
```

### Option 2: Component-by-Component

Deploy specific components for testing/learning:

```bash
# Deploy just Docker infrastructure
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags docker_infra

# Deploy Zookeeper
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags zookeeper

# Deploy Kafka
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags kafka

# Deploy PostgreSQL
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags postgres

# Deploy Debezium
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags debezium

# Deploy pgAdmin
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags pgadmin

# Deploy Kafka UI
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags kafka_ui
```

### Option 3: Modular Playbook

```bash
# Deploy a specific component using the component playbook
ansible-playbook -i hosts.yml playbook-deploy-component.yml \
  --vault-password-file=vault-pass \
  -e component=zookeeper
```

---

## Validation & Testing

### Health Checks

```bash
# Check all containers
docker ps | grep cdc

# Check individual service status
docker exec zk-cdc zkServer.sh status
docker exec kafka-cdc kafka-broker-api-versions.sh --bootstrap-server localhost:9092
docker exec postgres-cdc psql -U postgres -c "SELECT version();"
curl http://localhost:8083/connectors

# Check network connectivity
docker run --rm --network cdc-network busybox ping -c 1 172.20.0.3  # Kafka
docker run --rm --network cdc-network busybox ping -c 1 172.20.0.4  # PostgreSQL
```

### List Kafka Topics

```bash
docker exec kafka-cdc kafka-topics.sh --list --bootstrap-server localhost:9092

# Expected output:
# __consumer_offsets
# my_connect_configs
# my_connect_offsets
# my_connect_statuses
# postgres.public.users
# postgres.public.orders
# postgres.public.products
```

### Test CDC Flow

```bash
# 1. Connect to PostgreSQL
psql -h localhost -p 5433 -U postgres -d cdc_db

# 2. Insert test data
INSERT INTO public.users (name, email) VALUES ('John Doe', 'john@example.com');
INSERT INTO public.orders (user_id, amount) VALUES (1, 99.99);

# 3. Monitor Kafka topic
docker exec kafka-cdc \
  kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic postgres.public.users \
  --from-beginning

# Expected: You should see CDC events (create, update, delete) from PostgreSQL
```

### Check Debezium Connector Status

```bash
# List connectors
curl http://localhost:8083/connectors

# Get connector details
curl http://localhost:8083/connectors/postgres-cdc-connector

# Get connector status
curl http://localhost:8083/connectors/postgres-cdc-connector/status

# Expected: "state": "RUNNING"
```

---

## Access Portals

### 1. pgAdmin (Database Management)

**URL**: http://localhost:5050  
**Login**: admin@cdc-learning.local / <PGADMIN_DEFAULT_PASSWORD>  
**Features**:
- Manage PostgreSQL databases
- View tables, functions, replication slots
- Execute queries
- Monitor logs

### 2. Kafka UI (Kafka Monitoring)

**URL**: http://localhost:8080  
**Features**:
- View Kafka cluster overview
- Browse topics and partitions
- View messages in real-time
- Monitor consumer groups
- Monitor producers

### 3. Debezium REST API

**Base URL**: http://localhost:8083  
**Key Endpoints**:
- `GET /connectors` - List all connectors
- `GET /connectors/postgres-cdc-connector` - Specific connector
- `GET /connectors/postgres-cdc-connector/status` - Connector status
- `GET /connectors/postgres-cdc-connector/tasks` - Active tasks

### 4. PostgreSQL CLI

```bash
psql -h localhost -p 5433 -U postgres -d cdc_db

# Useful queries:
SELECT * FROM pg_replication_slots;
SELECT * FROM pg_stat_replication;
SELECT * FROM pg_publication;
```

### 5. pgBadger (Log Analysis Portal)

**URL**: http://localhost:8888 (after running pgBadger setup playbook)  
**Features**:
- PostgreSQL log analysis
- Query statistics
- Slow query detection
- Performance recommendations
- Multi-cluster analysis ready

---

## Advanced Usage

### Modify Configuration Mid-Deployment

```bash
# Edit vars/main.yml
vi vars/main.yml

# Redeploy specific component
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags kafka  # Redeploy only Kafka with new config
```

### Add More Kafka Topics

```bash
# Edit vars/main.yml
vi vars/main.yml

# Add to kafka_topics:
kafka_topics:
  - name: "postgres.public.users"
    partitions: 1
    replication_factor: 1
  - name: "postgres.public.orders"
    partitions: 1
    replication_factor: 1
  - name: "postgres.public.products"  # NEW
    partitions: 2
    replication_factor: 1

# Redeploy Kafka
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags kafka
```

### Setup pgBadger

```bash
# Run the pgBadger setup playbook
ansible-playbook -i hosts.yml playbook-setup-pgbadger.yml \
  --vault-password-file=vault-pass

# Generate log analysis
docker exec pgadmin4-cdc /tmp/pgbadger_config.sh

# Start web server inside pgAdmin
docker exec -d pgadmin4-cdc python3 /tmp/pgbadger_web_server.py

# Access reports
open http://localhost:8888
```

### Add a New PostgreSQL Instance to pgBadger

1. Deploy the new PostgreSQL container with log exports
2. Mount logs in pgAdmin container
3. Modify pgBadger analysis script to include new log sources
4. Regenerate reports

---

## Troubleshooting

### Issue: Container fails to start

```bash
# Check container logs
docker logs <container-name>

# Example:
docker logs postgres-cdc
docker logs debezium-connect
docker logs kafka-cdc

# Restart container
docker restart <container-name>
```

### Issue: Debezium connector not connecting to PostgreSQL

```bash
# Check connector status
curl http://localhost:8083/connectors/postgres-cdc-connector/status | jq

# Common issues:
# 1. Password mismatch - verify in sensitive-values
# 2. PostgreSQL not ready - wait 30 seconds
# 3. WAL level not 'logical' - check postgresql.conf

# Recreate connector
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-connector
# Then redeploy
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags debezium
```

### Issue: Kafka topics not receiving messages

```bash
# Check Debezium logs
docker logs debezium-connect | tail -50

# Verify publication exists in PostgreSQL
docker exec postgres-cdc \
  psql -U postgres -d cdc_db -c "SELECT * FROM pg_publication;"

# Verify replication slot exists
docker exec postgres-cdc \
  psql -U postgres -d cdc_db -c "SELECT * FROM pg_replication_slots;"

# Verify REPLICA IDENTITY on tables
docker exec postgres-cdc \
  psql -U postgres -d cdc_db -c "SELECT schemaname, tablename, pg_relation_replica_identity(('\"' || schemaname || '\".\"' || tablename || '\"')::regclass) FROM pg_tables WHERE schemaname='public';"
```

### Issue: Network connectivity problems

```bash
# Test network access between containers
docker run --rm --network cdc-network busybox \
  ping -c 1 kafka-cdc

# If fails, recreate network
docker network rm cdc-network
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass \
  --tags docker_infra
```

### Issue: "Port already in use"

```bash
# Find what's using the port
lsof -i :8083  # Debezium example

# Either:
# 1. Kill the process
kill -9 <PID>

# 2. Change port in vars/main.yml
vi vars/main.yml
# Change debezium_host_mapping_port to different value
# Then redeploy

# 3. Stop conflicting container
docker stop <container-name>
```

---

## Cleanup

### Remove Containers Only (Keep Volumes for Data Persistence)

```bash
ansible-playbook -i hosts.yml playbook-cleanup.yml \
  --vault-password-file=vault-pass
```

### Remove Containers and Volumes

```bash
ansible-playbook -i hosts.yml playbook-cleanup.yml \
  --vault-password-file=vault-pass \
  -e cleanup_volumes=true
```

### Remove Everything (Containers, Volumes, Network)

```bash
ansible-playbook -i hosts.yml playbook-cleanup.yml \
  --vault-password-file=vault-pass \
  -e cleanup_volumes=true \
  -e cleanup_network=true
```

### Manual Cleanup

```bash
# Stop all containers
docker stop zk-cdc kafka-cdc postgres-cdc debezium-connect pgadmin4-cdc kafka-ui-cdc

# Remove containers
docker rm zk-cdc kafka-cdc postgres-cdc debezium-connect pgadmin4-cdc kafka-ui-cdc

# Remove volumes
rm -rf ~/cdc-volumes

# Remove network
docker network rm cdc-network
```

---

## Expected Output Examples

### Successful Deployment

```
PLAY [Deploy Full Debezium CDC Stack] ****

TASK [Display deployment start message] ****
ok: [localhost] =>
╔════════════════════════════════════════════════════════════════╗
║  Deploying Debezium CDC Learning Infrastructure               ║
║  Full Stack: Docker, Zookeeper, Kafka, PostgreSQL,            ║
║             Debezium, pgAdmin, Kafka UI                       ║
╚════════════════════════════════════════════════════════════════╝

TASK [roles/docker_infrastructure : Create Docker network] ****
changed: [localhost]

TASK [roles/zookeeper : Deploy Zookeeper container] ****
changed: [localhost]

...

TASK [Display deployment completion message] ****
ok: [localhost] =>
╔════════════════════════════════════════════════════════════════╗
║  ✓ Debezium CDC Infrastructure Deployed Successfully!          ║
║                                                                ║
║  Access Points:                                                ║
║  • pgAdmin:        http://localhost:5050                       ║
║  • Kafka UI:       http://localhost:8080                       ║
║  • Debezium REST:  http://localhost:8083/connectors            ║
║  • PostgreSQL:     localhost:5433                              ║
║  • Kafka:          localhost:29092                             ║
║  • Zookeeper:      localhost:2181                              ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

PLAY RECAP ****
localhost : ok=35 changed=15 unreachable=0 failed=0
```

---

## File Structure

```
Debezium-CDC-Kafka/
├── README.md                      # This file
├── ansible.cfg                    # Ansible configuration
├── hosts.yml                      # Inventory (local containers)
├── vault-pass                     # Vault password file
├── sensitive-values               # Encrypted credentials
├── sensitive-values-sample        # Template for credentials
├── vars/
│   └── main.yml                   # Main configuration
├── roles/
│   ├── docker_infrastructure/     # Docker network setup
│   │   ├── defaults/main.yml
│   │   └── tasks/main.yml
│   ├── zookeeper/                 # Zookeeper deployment
│   │   ├── defaults/main.yml
│   │   └── tasks/main.yml
│   ├── kafka/                     # Kafka broker deployment
│   │   ├── defaults/main.yml
│   │   └── tasks/main.yml
│   ├── postgres_source/           # PostgreSQL source DB
│   │   ├── defaults/main.yml
│   │   ├── tasks/main.yml
│   │   └── templates/
│   │       ├── postgresql.conf
│   │       └── pg_hba.conf
│   ├── debezium/                  # Debezium connector
│   │   ├── defaults/main.yml
│   │   └── tasks/main.yml
│   ├── pgadmin/                   # pgAdmin deployment
│   │   ├── defaults/main.yml
│   │   └── tasks/main.yml
│   └── kafka_ui/                  # Kafka UI deployment
│       ├── defaults/main.yml
│       └── tasks/main.yml
├── playbook-deploy-all.yml        # Full stack deployment
├── playbook-deploy-component.yml  # Component-by-component
├── playbook-cleanup.yml           # Cleanup infrastructure
├── playbook-setup-pgbadger.yml    # pgBadger setup
└── scripts/                       # (Optional) Validation scripts
    └── validate-deployment.sh     # Deployment checks
```

---

## Learning Objectives Achieved

After completing this setup, you'll understand:

1. ✅ How **Change Data Capture (CDC)** works with PostgreSQL
2. ✅ **Debezium** architecture and configuration
3. ✅ **Kafka** topics, partitions, and message consumption
4. ✅ **Logical replication** in PostgreSQL (WAL level, slots, publications)
5. ✅ **Debezium connectors** configuration and lifecycle
6. ✅ **Docker networking** for multi-service applications
7. ✅ **Ansible** for infrastructure automation
8. ✅ **pgBadger** for PostgreSQL log analysis
9. ✅ How to **monitor CDC flows** in real-time
10. ✅ **Troubleshooting** CDC issues

---

## License

Same as PostgreSQL-Learning repository

---

## Questions & Support

Refer to individual role documentation and inline comments in YAML files.

For CDC Learning:
- Debezium Docs: https://debezium.io/documentation/
- PostgreSQL Logical Replication: https://www.postgresql.org/docs/current/logical-replication.html
- Kafka Docs: https://kafka.apache.org/documentation/

---

**Last Updated**: 2026-05-08  
**Tested On**: macOS with Docker Desktop, Ansible 2.10+
