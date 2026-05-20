# Configuration Changes Checklist for Synchronous Standby Cluster

## Implementation Steps

### Step 1: Update Ansible Inventory ✓ or ✗

**File**: `playbook-install-pg-cluster-docker-etcd/hosts.yml`

**Current (Line 24-30):**
```yaml
standby:
  hosts:
    pg4:
      ansible_host: "127.0.0.1"
      ansible_port: 2224
      ip: "172.18.0.14"
      patroni_standby_cluster:
        host: "172.18.0.10"
        port: 5432
```

**Change To (ADD primary_slot_name):**
```yaml
standby:
  hosts:
    pg4:
      ansible_host: "127.0.0.1"
      ansible_port: 2224
      ip: "172.18.0.14"
      patroni_standby_cluster:
        host: "172.18.0.10"
        port: 5432
        primary_slot_name: "pg4_dr_slot"  # ← ADD THIS LINE
```

---

### Step 2: Create Replication Slot on Primary ✓ or ✗

**Command:**
```bash
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
  -c "SELECT * FROM pg_create_physical_replication_slot('"'"'pg4_dr_slot'"'"');"'
```

**Expected Output:**
```
 slot_name   | lsn
─────────────┼─────
 pg4_dr_slot | 0/...
(1 row)
```

---

### Step 3: Verify Slot is Active ✓ or ✗

**Command:**
```bash
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
  -c "SELECT slot_name, slot_type, active, retained_bytes FROM pg_replication_slots;"'
```

**Expected Output:**
```
  slot_name   | slot_type | active | retained_bytes
──────────────┼───────────┼────────┼────────────────
 pg4_dr_slot  | physical  | t      | 0
```

---

### Step 4: Deploy Updated Configuration ✓ or ✗

**Option A: Update running config (immediate, temporary)**
```bash
# No need - slot just needs to exist
# pg4 automatically picks it up on reconnect
```

**Option B: Persist via Ansible (recommended)**
```bash
cd playbook-install-pg-cluster-docker-etcd

ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml \
  --vault-password-file=vault-pass
```

---

### Step 5: Verify on Standby ✓ or ✗

**Check pg4 is using the slot:**
```bash
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
  -c "SELECT slot_name, active FROM pg_replication_slots WHERE slot_name = '"'"'pg4_dr_slot'"'"';"'
```

**Expected: active = true ✅**

---

## Verification Checklist

- [ ] hosts.yml updated with `primary_slot_name`
- [ ] Slot created on primary
- [ ] Slot shows `active = true`
- [ ] pg4 replication streaming normally
- [ ] No errors in pg1 logs
- [ ] No errors in pg4 logs

---

## Rollback (if needed)

**Drop the slot:**
```bash
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
  -c "SELECT pg_drop_replication_slot('"'"'pg4_dr_slot'"'"');"'
```

---

## Timeline

- **Time to implement**: ~5 minutes
- **Downtime required**: None
- **Risk level**: Low
- **Rollback time**: < 1 minute
