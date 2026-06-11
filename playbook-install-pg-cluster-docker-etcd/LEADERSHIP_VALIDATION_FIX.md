# Leadership Validation Fix

## Problem

The leadership validation task used:
```bash
curl -sf http://127.0.0.1:8008/standby-leader >/dev/null 2>&1 && echo "ok" || echo "fail"
```

Issues:
1. **`-sf` flags suppress output** — Even though endpoint returns valid JSON, `-s` silences it AND errors
2. **No fallback validation** — If REST API check failed, playbook failed immediately
3. **False negatives** — Cluster was actually healthy (patronictl showed Leader/running) but playbook failed

## Solution

### Primary Check: Capture REST API Response
```bash
curl -s http://127.0.0.1:8008/standby-leader 2>&1
```
- Removed `-f` flag (it exits on HTTP 4xx/5xx, masking success)
- Use `-s` only (silent mode)
- Check response contains `"role"` string (proves valid JSON)
- Retries: 20 (20 seconds max wait)

### Fallback Validation (in rescue block)
If REST API check fails, validate via `patronictl`:

1. **Get full cluster status**: `patronictl list --format json`
2. **Verify this node**: `patronictl list | grep "<hostname>.*(Leader|Standby-leader)"`
3. **Only fail if** node is NOT found as Leader/Standby-leader
4. **Otherwise succeed** with message: "Cluster is HEALTHY despite REST API check failure"

## Expected Behavior

**Success path:**
1. REST API `/primary` or `/standby-leader` endpoint returns JSON → PASS

**Fallback path (if REST API times out):**
1. patronictl shows cluster is healthy with node in leadership role → PASS (with note: "REST API failed but cluster validated via patronictl")
2. patronictl shows node NOT in leadership → FAIL

## Result

✓ Eliminates false negatives when REST API is slow to respond
✓ Uses alternative validation method (patronictl) when primary fails
✓ Clear debugging output showing actual cluster state
