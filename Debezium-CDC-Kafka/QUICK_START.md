# Quick Start Guide - Debezium CDC Infrastructure

**Total Setup Time**: ~5 minutes  
**Prerequisites**: Docker, Ansible, Python3

## 🚀 5-Step Quick Start

### Step 1: Navigate to Project

```bash
cd ~/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka
```

### Step 2: Prepare Credentials (1 min)

```bash
# Edit sensitive values
cat > sensitive-values << 'EOF'
PG_SUPERUSER_PASSWORD: "ChangeMe_PostgresAdmin123!"
PG_REPLICATION_PASSWORD: "ChangeMe_Replication456!"
PG_APP_USER_PASSWORD: "ChangeMe_AppUser789!"
PGADMIN_DEFAULT_EMAIL: "admin@cdc-learning.local"
PGADMIN_DEFAULT_PASSWORD: "ChangeMe_PgAdmin123!"
KAFKA_BROKER_USERNAME: "kafka_user"
KAFKA_BROKER_PASSWORD: "ChangeMe_Kafka123!"
DEBEZIUM_CONNECTOR_USERNAME: "debezium_user"
DEBEZIUM_CONNECTOR_PASSWORD: "ChangeMe_Debezium123!"
EOF

# Encrypt with vault
ansible-vault encrypt sensitive-values --vault-password-file=vault-pass
```

### Step 3: Deploy All Services (3-4 min)

```bash
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass
```

**Expected Output**: ✓ All 7 containers running and healthy

### Step 4: Validate Deployment (1 min)

```bash
./scripts/validate-deployment.sh

# Or quick status
./scripts/quick-status.sh
```

**Expected**: All services show ✓ PASSED

### Step 5: Test CDC Flow (1 min)

```bash
./scripts/test-cdc-flow.sh
```

**Expected**: Data flows from PostgreSQL → Kafka ✓

## 🌐 Access Your Infrastructure

Open these in browser:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Database Admin** | http://localhost:5050 | admin@cdc-learning.local / ChangeMe_PgAdmin123! |
| **Kafka Topics** | http://localhost:8080 | No auth required |
| **Debezium API** | http://localhost:8083 | No auth required |

## 💾 Connect with PostgreSQL CLI

```bash
psql -h localhost -p 5433 -U postgres -d cdc_db
# Password: ChangeMe_PostgresAdmin123!

# View tables
\dt
SELECT * FROM pg_tables WHERE schemaname='public';
```

## 📊 Test CDC in Action

```bash
# Terminal 1: Watch Kafka messages
docker exec kafka-cdc kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic postgres.public.users \
  --from-beginning

# Terminal 2: Insert data in PostgreSQL
psql -h localhost -p 5433 -U postgres -d cdc_db << EOF
INSERT INTO public.users (name, email) VALUES ('Test User', 'test@example.com');
INSERT INTO public.orders (user_id, amount) VALUES (1, 99.99);
EOF

# Terminal 1: You'll see CDC events appear! 🎉
```

## ⚙️ Component-by-Component Deployment

If you want to understand each component:

```bash
# Just Docker network
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass --tags docker_infra

# Add Zookeeper (wait 30s)
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass --tags zookeeper

# Add Kafka (wait 30s)
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass --tags kafka

# Continue with postgres, debezium, pgadmin, kafka_ui...
```

## 🔍 Monitor in Real-Time

```bash
# Watch all containers
watch docker ps

# View container logs
docker logs -f postgres-cdc
docker logs -f debezium-connect
docker logs -f kafka-cdc

# Check Debezium connector status
curl http://localhost:8083/connectors/postgres-cdc-connector/status | jq

# List Kafka topics
docker exec kafka-cdc kafka-topics.sh --list --bootstrap-server localhost:9092
```

## 📚 Advanced Features

### Setup pgBadger (PostgreSQL Log Analysis)

```bash
ansible-playbook -i hosts.yml playbook-setup-pgbadger.yml \
  --vault-password-file=vault-pass

# Then access at http://localhost:8888
```

### Change Configuration

```bash
vi vars/main.yml
# Edit any settings, then redeploy

# For example, change PostgreSQL port from 5433 to 5434
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass --tags postgres
```

### Add More Kafka Topics

```bash
vi vars/main.yml
# Under kafka_topics, add new topics

# Redeploy Kafka
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass --tags kafka
```

## 🧹 Clean Up

```bash
# Keep data, remove containers
ansible-playbook -i hosts.yml playbook-cleanup.yml \
  --vault-password-file=vault-pass

# Remove everything including data
ansible-playbook -i hosts.yml playbook-cleanup.yml \
  --vault-password-file=vault-pass -e cleanup_volumes=true -e cleanup_network=true
```

## 🐛 Quick Troubleshooting

### Service won't start?

```bash
# Check logs
docker logs <container-name>

# Restart service
docker restart <container-name>

# Full redeploy of that component
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass --tags <component>
```

### Password doesn't work?

```bash
# Check vault file
ansible-vault view sensitive-values --vault-password-file=vault-pass

# If wrong password, edit and re-encrypt
ansible-vault rekey sensitive-values --vault-password-file=vault-pass
```

### Port already in use?

```bash
# Find what's using port
lsof -i :8083  # Example for Debezium

# Change port in vars/main.yml
vi vars/main.yml
# Change debezium_host_mapping_port to different value

# Redeploy
ansible-playbook -i hosts.yml playbook-deploy-all.yml \
  --vault-password-file=vault-pass --tags debezium
```

## 📖 Full Documentation

See **README.md** for:
- Detailed architecture
- All configuration options
- Complete troubleshooting guide
- Learning objectives
- Advanced usage

## ✅ Success Checklist

After Quick Start, verify:

- [ ] All 7 containers running: `docker ps | grep cdc`
- [ ] pgAdmin accessible: http://localhost:5050
- [ ] Kafka UI accessible: http://localhost:8080
- [ ] Can connect to PostgreSQL: `psql -h localhost -p 5433 -U postgres -d cdc_db`
- [ ] Debezium API responds: `curl http://localhost:8083/connectors`
- [ ] Test data flows to Kafka: `./scripts/test-cdc-flow.sh`
- [ ] Validation passes: `./scripts/validate-deployment.sh`

---

**You're now ready to learn CDC! 🚀**

Next steps:
1. Read README.md for full documentation
2. Explore the UI portals
3. Run the test-cdc-flow.sh script
4. Insert test data and watch it flow through Kafka
5. Check pgBadger logs after setup

Questions? Check troubleshooting in README.md
