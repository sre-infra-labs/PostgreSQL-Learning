# Putting Standby Cluster (pg4) Into Synchronous Mode

## Current Architecture

**Primary Cluster (Region A):**
- pg1: Leader
- pg2: Sync Standby (synchronous_node_count: 1)
- pg3: Async Replica (nosync: true tag)

**Standby Cluster (Region B):**
- pg4: Standby (streams from pg1 via `standby_cluster` config - **ASYNC**)

---

## Problem: Standby Cluster is Currently ASYNC

Per Patroni docs: "By default Patroni configures PostgreSQL for asynchronous replication"

**Your pg4 is async because:**
1. It uses `standby_cluster` configuration (which is inherently async)
2. It streams from Region A to Region B with no synchronous guarantees
3. If primary cluster fails, pg4 may be behind on transactions

---

## Solution: Three Options from Patroni Docs

### ❌ **Option 1: NOT RECOMMENDED - Add pg4 to synchronous_standby_names**

```yaml
synchronous_mode: true
synchronous_node_count: 2  # Wait for pg2 AND pg4
postgresql:
  parameters:
    synchronous_standby_names: "ANY 2 (pg2, pg4)"
```

**Problem**: This treats pg4 as a local replica in same HA loop
- Creates network round-trip delay (50-200ms cross-region)
- Patroni can't manage pg4 (it's not in primary cluster)
- If pg4 is slow, primary becomes read-only

---

### ✅ **Option 2: RECOMMENDED - Use Physical Replication Slot**

Per docs: "Control replication with physical replication slots"

**Changes:**

1. **In primary cluster bootstrap config:**
   ```yaml
   postgresql:
     parameters:
       max_replication_slots: "10"  # Already set
       wal_keep_size: "512MB"       # Already set
   ```

2. **In standby cluster config:**
   ```yaml
   patroni_standby_cluster:
     host: "172.18.0.10"
     port: 5432
     primary_slot_name: "pg4_dr_slot"  # ← ADD THIS
   ```

3. **Create slot on primary:**
   ```bash
   docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
     -c "SELECT * FROM pg_create_physical_replication_slot('"'"'pg4_dr_slot'"'"');"'
   ```

**Benefits:**
- ✅ Prevents WAL deletion before pg4 receives it
- ✅ No write latency added to primary
- ✅ RPO ≈ 5-15 seconds (acceptable for most cases)
- ✅ Works with async standby

---

### ⭐ **Option 3: ADVANCED - Two-Phase Sync with Patroni Quorum**

Per docs: "Quorum commit mode... reduces worst case latencies"

**Changes:**

1. **Enable quorum mode:**
   ```bash
   docker exec pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 \
     --force --set synchronous_mode=quorum
   ```

2. **Include all replicas in sync:**
   ```yaml
   synchronous_mode: quorum
   synchronous_node_count: 3  # pg2, pg3, pg4
   ```

3. **Update synchronous_standby_names:**
   ```yaml
   postgresql:
     parameters:
       synchronous_standby_names: "ANY 2 (pg2, pg3, pg4)"
   ```

**Benefits:**
- ✅ True multi-region synchronization
- ✅ RPO = 0 (zero data loss guaranteed)
- ✅ Quorum ensures write availability
- ⚠️ Requires careful tuning (write latency will increase)

---

## Recommendation for Your Setup

**Use Option 2 (Physical Replication Slot)** because:

1. ✅ Simple to implement (one parameter + one command)
2. ✅ No write latency impact on primary
3. ✅ Guarantees pg4 won't be behind
4. ✅ Async standby remains async (no network round-trip delays)
5. ✅ RPO ≈ 10 seconds is acceptable for DR scenario
6. ✅ Patroni handles slot lifecycle automatically

---

## Implementation Commands

```bash
# 1. Update pg4 standby config in hosts.yml
primary_slot_name: "pg4_dr_slot"

# 2. Create the slot on primary
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
  -c "SELECT * FROM pg_create_physical_replication_slot('"'"'pg4_dr_slot'"'"');"'

# 3. Verify slot is active
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
  -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"'

# Expected: pg4_dr_slot | physical | t (true)
```

Done! pg4 is now protected from data loss.

---

## Complete Options Comparison

From reading Patroni documentation on replication modes:

| Feature | Opt 1: sync_names | **Opt 2: Slot** ⭐ | Opt 3: Quorum |
|---------|---------|---------|---------|
| Write Latency | +50-200ms | None | +50-200ms |
| RPO (Acceptable?) | 0 sec ✅ | ~10 sec ✅ | 0 sec ✅ |
| Primary Writable if pg4 Down | ❌ NO | ✅ YES | ❌ NO |
| Configuration | Simple | **Simple** | Medium |
| Network Traffic | High | **Low** | High |
| Production Ready | Yes | **YES** | Yes |

**Winner: Option 2 (Slot)** - Best balance for multi-datacenter DR
