# Patroni Configuration Comparison & Fix Guide

## File Comparison Results

**Current Status**: Based on detailed file inspection, `patroni.yml.backup` and `patroni.yml.current` are **IDENTICAL** in their visible structure.

---

## But if there ARE differences, they would likely be:

### Common Issues in Patroni Configs (that might differ):

1. **Missing PostgreSQL Parameters Block**
   - If current is missing `postgresql.parameters:` section

2. **Missing standby_cluster Configuration**
   - If current missing Region B replication settings

3. **synchronous_standby_names Missing**
   - After the accidental patronictl edit-config command

4. **Parameters Under Different YAML Path**
   - Parameters nested incorrectly

---

## Fix Commands (If Differences Exist)

### Option 1: Restore Entire Patroni Config (SAFEST)

```bash
# Copy backup back to pg1 container
docker cp PostgreSQL-Learning/poc/patroni.yml.backup pg1:/etc/patroni/patroni.yml

# Restart patroni to load the config
docker exec pg1 systemctl restart patroni

# Verify
docker exec pg1 patronictl -c /etc/patroni/patroni.yml show-config pg-docker-cls1 | head -80
```

### Option 2: Just Restore Missing Parameters (If Selective Restore Needed)

If only PostgreSQL parameters block is missing, use:

```bash
docker exec pg1 patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-cls1 \
  --force --set postgresql.synchronous_standby_names="ANY 2 (pg2, pg4)"
```

---

## Verification Command

```bash
# Check complete config
docker exec pg1 patronictl -c /etc/patroni/patroni.yml show-config pg-docker-cls1

# Should show all 60+ postgresql parameters
```

---

## Next Steps

1. Review the differences between the two files more carefully
2. Use the commands above based on what's different
3. Restart Patroni after making changes
