# Standby Cluster Playbook Bug Fix

## Problem Identified

**`playbook-install-standby-cluster.yml` was installing a PRIMARY cluster instead of a STANDBY cluster.**

### Root Cause

The Patroni template (`patroni.yml.j2` line 60) contains a condition:

```jinja2
{% if inventory_hostname in groups['standby_cluster'] and ... and (_cluster_is_standby | default(false) | bool) %}
  standby_cluster:
    host: {{ patroni_standby_cluster.host }}
    ...
{% endif %}
```

This condition checks for `_cluster_is_standby | default(false)` but **this variable was NEVER defined** in the main cluster installation playbooks!

**Result:**
- `_cluster_is_standby` defaulted to `false`
- `standby_cluster` config block was NEVER included in patroni.yml
- Patroni on pg4 behaved as a primary cluster instead of standby
- No streaming from primary cluster occurred

### Why This Wasn't Caught Earlier

The variable `_cluster_is_standby` IS defined in `playbook-add-replicas.yml` (line 147-148):
```yaml
_cluster_is_standby: >-
  {{ _patroni_check.json.role | default('') in ['standby_leader', 'replica'] }}
```

But it's **only defined for that specific playbook**, not in the cluster installation playbooks.

## Solution Applied

Added explicit `vars:` section to both cluster playbooks:

### `playbook-install-standby-cluster.yml` (line 14-16)
```yaml
vars:
  # Signal to Patroni template that this is a standby cluster
  _cluster_is_standby: true
```

### `playbook-install-primary-cluster.yml` (line 10-12)
```yaml
vars:
  # Signal to Patroni template that this is a primary cluster (not standby)
  _cluster_is_standby: false
```

## Result

✅ Standby cluster will now include `standby_cluster:` config block in patroni.yml  
✅ Patroni on standby nodes will stream from primary cluster  
✅ Primary cluster will NOT have `standby_cluster:` config  
✅ Proper cluster architecture established

## Test

```bash
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true
```

Then verify:
```bash
docker exec docpg-cls1-pg4 cat /etc/patroni/patroni.yml | grep -A 5 "standby_cluster:"
```

Should show the standby_cluster block with primary cluster connection details.
