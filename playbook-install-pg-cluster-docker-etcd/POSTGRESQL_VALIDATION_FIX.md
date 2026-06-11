# PostgreSQL Validation Task Fixes

## Problems Fixed

### 1. Silenced Failures with `ignore_errors: true`
**Before:**
```yaml
register: _pg_check_leader
ignore_errors: true  # ← Masks failure, playbook continues
```
**After:** Removed `ignore_errors: true` — failures now cause playbook to stop

### 2. Lost Diagnostic Output
**Before:**
```bash
psql -h 127.0.0.1 -U postgres -c "SELECT version();" >/dev/null 2>&1 && echo "ok" || echo "fail"
# Output redirected to /dev/null → no visibility on errors
```
**After:**
```bash
psql -h 127.0.0.1 -U postgres -c "SELECT version();" 2>&1
# Capture full output (stdout + stderr) for diagnosis
```

### 3. No Rescue Block for Error Handling
**Before:** No rescue block — if psql failed, task output was lost

**After:** Added comprehensive rescue block that:
1. Collects PostgreSQL service logs (`journalctl -u postgresql`)
2. Collects Patroni logs (for bootstrap context)
3. Displays captured logs via DEBUG task
4. **FAILS THE PLAYBOOK** with clear error message

## Changes Applied

**File:** `roles/pg_cluster/tasks/custom/patroni.yml`

### Leader PostgreSQL Validation (Lines 248-300)
- Removed `ignore_errors: true`
- Changed psql to capture full output
- Changed until condition: `"PostgreSQL" in stdout` (better than echo check)
- Added rescue block with PostgreSQL + Patroni logs
- Playbook now STOPS on failure

### Replica PostgreSQL Validation (Lines 486-519)
- Same changes as leader
- Captures output, logs, and fails appropriately

## Result

✅ Failures no longer hidden
✅ Root causes visible immediately (PostgreSQL logs)
✅ Patroni bootstrap context visible (why Patroni couldn't start PG)
✅ Playbook fails fast instead of reporting false success
✅ docpg-cls1-pg5 PostgreSQL startup issue will now be caught
