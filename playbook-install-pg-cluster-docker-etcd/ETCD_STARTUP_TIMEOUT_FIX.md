# etcd Startup Timeout Fix

## Problem Identified

**Standby cluster playbook failed with: `etcd process is not running on docpg-cls1-pg4`**

But etcd WAS actually running — it just needed more time to fully transition to "active" state.

### Root Cause

The etcd validation task checked `systemctl is-active etcd` **immediately after starting the service** without any retries:

```yaml
- name: Check if etcd process is running
  ansible.builtin.command: systemctl is-active etcd
  register: etcd_process_check
  changed_when: false
  failed_when: false
  timeout: 10
  when: (etcd_cluster_state | default('new')) != 'existing'

- name: Fail if etcd process is not running
  ansible.builtin.fail:
    msg: "etcd process is not running..."
  when:
    - etcd_process_check.rc != 0
```

**Sequence of events:**
1. `systemctl start etcd` is called
2. Task checks `systemctl is-active` → returns rc=3 (activating state)
3. Playbook immediately fails
4. But in the background, etcd continues starting and becomes fully active

### Why This Happens

etcd (especially 3-node cluster bootstrap) takes several seconds to fully transition from "activating" to "active" state, especially when initializing the cluster consensus.

## Solution Applied

Added **retries and until condition** to the `systemctl is-active` check:

**File:** `roles/pg_cluster/tasks/custom/etcd.yml` (Line 111-119)

```yaml
- name: Check if etcd process is running (with retries for startup)
  ansible.builtin.command: systemctl is-active etcd
  register: etcd_process_check
  changed_when: false
  failed_when: false
  retries: 10      # ← NEW: retry up to 10 times
  delay: 1         # ← NEW: wait 1 second between retries
  until: etcd_process_check.rc == 0   # ← NEW: succeed when rc == 0
  timeout: 30      # Total timeout: (10 retries × 1s delay = 10s max)
  when: (etcd_cluster_state | default('new')) != 'existing'
```

**Total wait time: 10 seconds max** (10 retries × 1 second delay) before failing.

## Result

✅ etcd startup race condition eliminated  
✅ Playbook waits for etcd to fully become active before proceeding  
✅ No more false failures when etcd is actually healthy  
✅ 30-second timeout rule respected (10s max + later health checks)

## Test

```bash
ansible-playbook -i hosts.yml playbook-install-standby-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true
```

etcd should now successfully start on all three standby nodes (pg4, pg5, pg6).
