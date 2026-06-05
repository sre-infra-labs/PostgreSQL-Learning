# 🚀 Final Deployment Guide

All implementation is complete. Follow these exact commands to deploy.

## Prerequisites Check

```bash
# Verify Docker
docker --version
docker-compose --version

# Verify Ansible
ansible --version
python3 --version
```

## Deployment Commands

### Option 1: Full Stack Deployment (Recommended)

```bash
cd ~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka

# Make deploy script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh
```

### Option 2: Manual Deployment

```bash
cd ~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka

# Verify vault password works
ansible-vault view sensitive-values --vault-password-file=vault-pass | head -5

# Deploy full stack
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass -v

# Or deploy component by component
ansible-playbook -i hosts.yml playbook-deploy-component.yml \
  --vault-password-file=vault-pass -e component=docker_infra

ansible-playbook -i hosts.yml playbook-deploy-component.yml \
  --vault-password-file=vault-pass -e component=kafka_ecosystem

ansible-playbook -i hosts.yml playbook-deploy-component.yml \
  --vault-password-file=vault-pass -e component=postgres

ansible-playbook -i hosts.yml playbook-deploy-component.yml \
  --vault-password-file=vault-pass -e component=pgadmin
```

## Post-Deployment Validation

```bash
# Run validation script
./scripts/validate-deployment.sh

# Quick status check
./scripts/quick-status.sh

# Test CDC flow
./scripts/test-cdc-flow.sh
```

## Access Services After Deployment

| Service | URL/Port | Credentials |
|---------|----------|-------------|
| Kafka UI | http://localhost:8080 | No auth |
| Debezium REST API | http://localhost:8083 | No auth |
| pgAdmin | http://localhost:5050 | Check vault file |
| PostgreSQL | localhost:5433 | Check vault file |

## View Vault Credentials

```bash
ansible-vault view sensitive-values --vault-password-file=vault-pass
```

**Expected format:**
```
PG_SUPERUSER_PASSWORD: "Pg@Superuser#2024!"
PG_REPLICATION_PASSWORD: "Pg@Replication#2024!"
PGADMIN_DEFAULT_EMAIL: "admin@debezium-cdc.local"
PGADMIN_DEFAULT_PASSWORD: "PgAdmin@2024!"
... and more
```

## Quick Troubleshooting

### Check Container Status
```bash
docker ps | grep cdc
```

### View Container Logs
```bash
# Kafka Ecosystem logs
docker logs kafka-ecosystem-cdc

# PostgreSQL logs
docker logs postgres-cdc

# pgAdmin logs
docker logs pgadmin4-cdc
```

### Check Docker Network
```bash
docker network ls | grep cdc-network
docker network inspect cdc-network
```

### Test Connectivity
```bash
# Test Zookeeper
docker run --rm --network cdc-network busybox nc -zv kafka-ecosystem-cdc 2181

# Test Kafka
docker run --rm --network cdc-network busybox nc -zv kafka-ecosystem-cdc 9092

# Test Debezium
curl http://localhost:8083/connectors

# Test PostgreSQL
psql -h localhost -p 5433 -U postgres -c "SELECT 1"
```

## Expected Deployment Output

After successful deployment, you should see:

✅ Docker infrastructure created (cdc-network)  
✅ Kafka Ecosystem running (Zookeeper + Kafka + Debezium + Kafka UI)  
✅ PostgreSQL source database running with CDC enabled  
✅ pgAdmin running for database management  
✅ All topics created (postgres.public.users, postgres.public.orders, postgres.public.products)  
✅ Debezium connector registered and running  

## Deployment Time

- Full stack: 5-10 minutes (includes Docker image pulls)
- Component by component: 2-3 minutes per component (after images cached)

## Next Steps

1. ✅ Run deployment using ./deploy.sh or manual commands above
2. ✅ Run validation scripts to verify all services
3. ✅ Read CDC-Using-Debezium-n-Kafka.md for CDC concepts
4. ✅ Access Kafka UI (http://localhost:8080) to monitor
5. ✅ Test CDC flow with ./scripts/test-cdc-flow.sh
6. ✅ Insert test data and observe CDC events in Kafka
7. ✅ Setup pgBadger with playbook-setup-pgbadger.yml (optional)

## Important Files

- **deploy.sh** - Master deployment script
- **playbook-deploy-all.yml** - Ansible playbook
- **vault-pass** - Vault password (Pa$$w0rd)
- **sensitive-values** - Encrypted credentials
- **vars/main.yml** - Configuration

## Support Documentation

- **START_HERE.md** - Orientation guide
- **CDC-Using-Debezium-n-Kafka.md** - CDC explanation
- **README.md** - Complete reference
- **IMPLEMENTATION_GUIDE.md** - Detailed steps

---

**Ready to deploy! Execute the commands above.** 🎉
