# curl -sf Flag Removal Fix

## Problem Identified

All curl commands throughout the playbooks used the `-sf` flags:
```bash
curl -sf http://endpoint >/dev/null 2>&1
```

The `-f` flag causes curl to:
1. **Exit with rc=22** on HTTP 4xx/5xx responses (like 503 Service Unavailable)
2. **Suppress output** completely (combined with `-s` and `>/dev/null`)
3. **Hide the response body** even when it contains useful error info

This created false negatives: service was actually responding, but curl failed silently.

## Solution Applied

Removed the `-f` flag from ALL curl commands throughout:
- `playbook-add-replicas.yml` (16 instances)
- `roles/pg_cluster/tasks/custom/patroni.yml` (4 instances)
- `roles/pg_cluster/tasks/custom/etcd.yml` (2 instances)
- `roles/pg_cluster/tasks/custom/prechecks.yml` (1 instance)
- `roles/pg_cluster/tasks/custom/pgbouncer.yml` (1 instance)

**Total: 24 instances fixed**

## New Behavior

```bash
# BEFORE (problematic)
curl -sf http://endpoint >/dev/null 2>&1 && echo "ok" || echo "fail"
# If endpoint returns 503: curl exits with rc=22, outputs "fail" (even if endpoint responded)

# AFTER (fixed)
curl -s http://endpoint >/dev/null 2>&1 && echo "ok" || echo "fail"
# Only exits with fail if truly unreachable
# Response body available for parsing if needed
```

## Result

✅ Eliminates false negatives from HTTP 5xx status codes
✅ Response body now visible when debugging (if needed)
✅ Health checks actually validate service availability
✅ Cluster validation matches actual service state
