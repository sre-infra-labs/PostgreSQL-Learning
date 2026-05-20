# Implementation Guide - CDC with Debezium & Kafka

**Status**: Production Ready  
**Last Updated**: 2026-05-08  
**Architecture**: Simplified with Unified Kafka Ecosystem

## Quick Facts

- **Vault Password**: Pa$$w0rd (in vault-pass)
- **Sudo Password**: Tessell@123
- **Localhost PostgreSQL**: Pa$$w0rd (postgres user)
- **Sensitive Values**: Encrypted in sensitive-values (view: `ansible-vault view sensitive-values --vault-password-file=vault-pass`)

## File Structure

```
├── vars/main.yml                    # All configurable variables
├── sensitive-values                 # Encrypted credentials (vault)
├── sensitive-values-sample          # Credential template
├── vault-pass                       # Vault password
├── ansible.cfg                      # Ansible settings
├── hosts.yml                        # Inventory
├── playbook-deploy-all.yml          # Full deployment
├── playbook-deploy-component.yml    # Component selection
├── playbook-cleanup.yml             # Cleanup
├── playbook-setup-pgbadger.yml      # pgBadger setup
├── CDC-Using-Debezium-n-Kafka.md    # CDC explained (UPDATED)
├── roles/
│   ├── docker_infrastructure/       # Docker network setup
│   ├── kafka_ecosystem/             # Zookeeper + Kafka + Debezium + Kafka UI
│   ├── postgres_source/             # PostgreSQL CDC source
│   └── pgadmin/                     # pgAdmin database GUI
└── scripts/
    ├── validate-deployment.sh
    ├── test-cdc-flow.sh
    └── quick-status.sh
```

## Deployment Steps

### Step 1: Verify Prerequisites

```bash
# Check Docker
docker --version
docker-compose --version

# Check Ansible
ansible --version
python3 --version

# Check vault file
ansible-vault view ~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka/sensitive-values --vault-password-file=~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka/vault-pass
```

### Step 2: Deploy Full Stack

```bash
cd ~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka

# Deploy everything
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass
```

### Step 3: Validate

```bash
# Check all services
./scripts/validate-deployment.sh

# Quick status
./scripts/quick-status.sh
```

### Step 4: Test CDC Flow

```bash
# Test end-to-end CDC
./scripts/test-cdc-flow.sh
```

## Architecture Changes from Original

### Before
- Separate containers: Zookeeper, Kafka, Debezium, Kafka UI
- 7 separate Ansible roles
- Complex orchestration

### After
- **Unified Kafka Ecosystem**: Single docker-compose coordinating 4 services
- **Simplified Roles**: 4 main roles (docker_infrastructure, kafka_ecosystem, postgres_source, pgadmin)
- **Cleaner Deployment**: Single role handles Zookeeper + Kafka + Debezium + Kafka UI

## Access Endpoints

| Service | URL | Credentials |
|---------|-----|-------------|
| Kafka UI | http://localhost:8080 | No auth |
| Debezium REST | http://localhost:8083 | No auth |
| pgAdmin | http://localhost:5050 | admin@debezium-cdc.local / [from vault] |
| PostgreSQL | localhost:5433 | postgres / [from vault] |
| Zookeeper | localhost:2181 | Internal |
| Kafka | localhost:29092 | Internal |

## Verify Vault Contents

```bash
# View all sensitive values
ansible-vault view sensitive-values --vault-password-file=vault-pass

# Expected output:
# PG_SUPERUSER_PASSWORD: "Pg@Superuser#2024!"
# PG_REPLICATION_PASSWORD: "Pg@Replication#2024!"
# PG_APP_USER_PASSWORD: "Pg@AppUser#2024!"
# PGADMIN_DEFAULT_EMAIL: "admin@debezium-cdc.local"
# PGADMIN_DEFAULT_PASSWORD: "PgAdmin@2024!"
# ... and more
```

## Component Selection (Individual Deployment)

```bash
# Deploy only Docker infrastructure
ansible-playbook -i hosts.yml playbook-deploy-component.yml \
  --vault-password-file=vault-pass -e component=docker_infra

# Deploy only Kafka Ecosystem (Zk + Kafka + Debezium + Kafka UI)
ansible-playbook -i hosts.yml playbook-deploy-component.yml \
  --vault-password-file=vault-pass -e component=kafka_ecosystem

# Deploy only PostgreSQL
ansible-playbook -i hosts.yml playbook-deploy-component.yml \
  --vault-password-file=vault-pass -e component=postgres

# Deploy only pgAdmin
ansible-playbook -i hosts.yml playbook-deploy-component.yml \
  --vault-password-file=vault-pass -e component=pgadmin
```

## Testing CDC Flow

### Automatic Test

```bash
./scripts/test-cdc-flow.sh
```

### Manual Test

```bash
# Terminal 1: Watch Kafka messages
docker exec -it kafka-ecosystem-cdc kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic postgres.public.users \
  --from-beginning

# Terminal 2: Insert data
psql -h localhost -p 5433 -U postgres -d cdc_db << 'SQL'
INSERT INTO public.users (name, email) VALUES ('Test User', 'test@example.com');
INSERT INTO public.orders (user_id, amount) VALUES (1, 99.99);
UPDATE public.users SET name='Updated User' WHERE id=1;
DELETE FROM public.users WHERE id=1;
SQL

# Terminal 1: Watch CDC events appear
```

## Documentation

- **CDC-Using-Debezium-n-Kafka.md** - Complete CDC explanation (UPDATED)
- **README.md** - Full infrastructure documentation
- **QUICK_START.md** - 5-minute setup guide
- **INDEX.md** - Navigation and reference
- **DELIVERABLES.md** - Project summary

## Configuration Changes

All editable in `vars/main.yml`:
- Network name and subnet
- Service versions and ports
- Database names and users (passwords from vault)
- Kafka topics
- pgAdmin settings
- pgBadger configuration
- Deployment flags

## Cleanup

```bash
# Remove containers (keep volumes)
ansible-playbook -i hosts.yml playbook-cleanup.yml \
  --vault-password-file=vault-pass

# Remove everything
ansible-playbook -i hosts.yml playbook-cleanup.yml \
  --vault-password-file=vault-pass -e cleanup_volumes=true -e cleanup_network=true
```

## Troubleshooting

### Docker Compose Error

If docker-compose fails, ensure volumes are properly created:
```bash
mkdir -p ~/cdc-volumes/{zookeeper,kafka,postgres,pgadmin,pgbadger}/{data,logs,reports}
```

### Connector Not Registering

1. Check Debezium logs:
   ```bash
   docker logs kafka-ecosystem-cdc | grep -i error
   ```

2. Verify PostgreSQL connectivity:
   ```bash
   psql -h 172.20.0.3 -U replication -d cdc_db -c "SELECT 1"
   ```

3. Check publication:
   ```bash
   psql -h localhost -p 5433 -U postgres -d cdc_db -c "SELECT * FROM pg_publication;"
   ```

### Network Issues

Ensure network exists:
```bash
docker network ls | grep cdc-network
# If missing, run docker_infrastructure role
```

## Next Steps

1. Review CDC-Using-Debezium-n-Kafka.md for detailed CDC concepts
2. Deploy infrastructure using playbook-deploy-all.yml
3. Run validation and test scripts
4. Explore Kafka UI at http://localhost:8080
5. Insert test data and watch CDC events
6. Setup pgBadger for PostgreSQL log analysis

---

**Ready to deploy! 🚀**
