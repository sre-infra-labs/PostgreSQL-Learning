# Service Validation Restructuring Summary

## Changes Made

### 1. **prechecks.yml** — Enhanced Cleanup with Service Validation
- Added explicit **CAPTURE & DEBUG** for each cleanup action
- Each removal task (Patroni stop, PostgreSQL data dir, etcd data dir, logs) now:
  - Captures result in a variable
  - Displays DEBUG output showing success/failure status
- etcd reachability check before Patroni key removal
- Patroni cluster keys removal from etcd with explicit feedback

### 2. **patroni.yml** — Restructured Leader & Replica Blocks
Separated monolithic blocks into **independent service validations**:

#### **LEADER** (docpg-cls1-pg4):
1. **Validate etcd** — service status + HTTP health → DEBUG
2. **Start Patroni** — systemd start + process check → DEBUG
3. **Validate Patroni REST API** — /cluster endpoint health → DEBUG
4. **Validate PostgreSQL** — psql connection test → DEBUG
5. **Validate Leader Election** — /primary or /standby-leader endpoint → DEBUG

#### **REPLICA** (docpg-cls1-pg5, pg6):
1. **Validate etcd** — service status + HTTP health → DEBUG
2. **Start Patroni** — systemd start + process check → DEBUG
3. **Validate Patroni REST API** — /cluster endpoint health → DEBUG
4. **Validate PostgreSQL** — psql connection test → DEBUG

## Key Principles Applied

✅ **Every shell/raw command captures result in variable**
✅ **Each captured result has explicit DEBUG task next to it**
✅ **Services validated independently (etcd → Patroni → PostgreSQL)**
✅ **Clear separation between leader and replica startup sequences**
✅ **Enhanced leadership election timeout from 5 → 20 retries**
✅ **Curl-based REST API checks (faster than uri module)**

## Ready for Testing

Run the standby cluster reinit:
```bash
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true
```

All service states and transitions will be visible via DEBUG output.
