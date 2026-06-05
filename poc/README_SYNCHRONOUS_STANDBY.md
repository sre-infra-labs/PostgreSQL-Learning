# Synchronous Standby Cluster Implementation Guide

## Documents in This Directory

1. **RECOMMENDATION_SUMMARY.md** ← START HERE
   - Executive summary of 3 options
   - Why Option 2 is recommended
   - Quick reference

2. **SYNCHRONOUS_STANDBY_CLUSTER_ANALYSIS.md**
   - Detailed analysis of all 3 options
   - Comparison table
   - Deep technical explanation from Patroni docs

3. **CONFIG_CHANGES_CHECKLIST.md**
   - Step-by-step implementation
   - Exact commands to run
   - Verification steps
   - Rollback procedure

4. **patroni.yml.backup** / **patroni.yml.current**
   - Reference configuration files
   - Both are currently identical

---

## Quick Start

### What You're Doing
Making pg4 (standby cluster in Region B) protected from data loss when primary cluster (pg1/pg2/pg3 in Region A) fails.

### Three Options from Patroni Docs

| Option | What It Does | RPO | Write Latency |
|--------|--------|-----|--------|
| 1: Add to sync_names | Make pg4 synchronous standby | 0 | **+50-200ms** ❌ |
| 2: Replication Slot ⭐ | Prevent WAL deletion until pg4 gets it | ~10s | **None** ✅ |
| 3: Quorum Mode | Distributed consensus across regions | 0 | **+50-200ms** ❌ |

### Recommended: Option 2 (Replication Slot)

**Why?**
- Standby cluster should NOT wait for primary writes (cross-region latency)
- Slot prevents WAL deletion automatically
- Patroni manages it - no ongoing operational overhead
- RPO ~10 seconds is acceptable for DR

### Implementation (5 minutes)

```bash
# 1. Add to hosts.yml under pg4 standby section:
primary_slot_name: "pg4_dr_slot"

# 2. Create slot on primary:
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
  -c "SELECT * FROM pg_create_physical_replication_slot('"'"'pg4_dr_slot'"'"');"'

# 3. Verify:
docker exec pg1 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.11 -p 5432 -U postgres postgres \
  -c "SELECT slot_name, active FROM pg_replication_slots;"'
```

Done! ✅

---

## Key Takeaway from Patroni Docs

> "When followers become inaccessible from the leader, the leader effectively becomes **read-only**"

This is why standby clusters in different regions should use replication slots, not synchronous_standby_names. You want the standby to be **safe without impacting primary availability**.

---

## Next Steps

1. Read `RECOMMENDATION_SUMMARY.md` for full context
2. Follow `CONFIG_CHANGES_CHECKLIST.md` for implementation
3. Test during next DR drill
4. Document results
