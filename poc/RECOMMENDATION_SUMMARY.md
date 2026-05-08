# Synchronous Standby Cluster - Final Recommendation

## Your Question
"Read the Patroni documentation on replication modes. What changes are required to put standby cluster into synchronous mode?"

## Answer from Documentation

You have **THREE OPTIONS**, but only **ONE is recommended** for your architecture.

---

## ✅ RECOMMENDED: Option 2 - Physical Replication Slot

**Why**: Best balance of safety, performance, and operational simplicity.

### Changes Required

**1. Update hosts.yml** (Line: pg4 standby config)
```yaml
patroni_standby_cluster:
  host: "172.18.0.10"
  port: 5432
  primary_slot_name: "pg4_dr_slot"  # ← ADD THIS
```

**2. Create replication slot on primary**
```bash
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
  -c "SELECT * FROM pg_create_physical_replication_slot('"'"'pg4_dr_slot'"'"');"'
```

**3. Verify slot is active**
```bash
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
  -c "SELECT slot_name, active, retained_bytes FROM pg_replication_slots;"'
```

### Benefits
- ✅ RPO ~10 seconds (acceptable for DR)
- ✅ NO write latency impact on primary
- ✅ Primary remains writable if pg4 is slow
- ✅ Patroni manages slot automatically
- ✅ Simple to implement

---

## Why NOT Option 1 (synchronous_standby_names)

Per Patroni docs:
> "If followers become inaccessible from the leader, the leader effectively becomes **read-only**"

Adding pg4 to primary's `synchronous_standby_names` means:
- Primary waits for pg4 to ack every write (50-200ms network)
- If pg4 is unreachable → primary CANNOT WRITE
- Cross-region WAN = unreliable → frequent write blocks
- ❌ Not suitable for multi-datacenter setup

---

## Why NOT Option 3 (Quorum Mode)

More complex than necessary:
- Requires `synchronous_mode: quorum` 
- Needs multiple quorum members
- Higher operational complexity
- Only needed for very complex HA scenarios

---

## Final Setup After Implementation

**Primary Cluster** (Region A):
- pg1: Leader (with sync to pg2)
- pg2: Sync Standby (synchronous_node_count: 1)
- pg3: Async Replica (nosync: true)

**Standby Cluster** (Region B):
- pg4: Standby with **physical replication slot protection**
  - RPO ~10 seconds
  - No write latency on primary
  - Automatic WAL retention via slot

**Result**: Balanced DR setup with zero operational overhead ✅
