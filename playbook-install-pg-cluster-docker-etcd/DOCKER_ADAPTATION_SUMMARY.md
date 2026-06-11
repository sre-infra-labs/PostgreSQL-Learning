# Docker Adaptation Summary for playbook-add-replicas.yml

**Date**: 2026-06-11  
**Status**: ✅ COMPLETE

## Overview

Refactored `playbook-add-replicas.yml` to work with Docker containers using the Ansible `community.docker.docker` connection plugin. The original playbook was written for Podman with direct localhost access to etcd/Patroni endpoints. All tasks now execute commands **inside containers** via `docker exec`.

## Key Changes

### 1. **PREFLIGHT Health Checks (Lines 72-134)**
   - **Old**: `ansible.builtin.uri` with direct HTTP to localhost:2379 and localhost:restapi_port
   - **New**: `docker exec <container> curl -sf <endpoint>` wrapped in shell blocks
   - **Why**: Docker connection plugin reaches containers via `docker exec`, not TCP

### 2. **Guard Checks in Play 2 (Lines 241-268)**
   - **Old**: `delegate_to` and `ansible.builtin.uri`
   - **New**: `docker exec {{ _leader }} curl -sf <endpoint>` with explicit health checking
   - **Result**: Verifies leader etcd/Patroni health before registering new replicas

### 3. **etcd Cluster Computation (Lines 276-302)**
   - **Old**: Direct `etcdctl` commands via `delegate_to`
   - **New**: `docker exec {{ _leader }} bash -c '...'` with inline bash script
   - **Critical**: Field separator changed from `', '` to `", "` inside docker exec bash -c context

### 4. **etcd Member Add (Lines 335-365)**
   - **Old**: Direct `etcdctl member add` via `delegate_to`
   - **New**: `docker exec {{ _leader }} bash -c '...'` with quoted field separators
   - **Learner registration**: Register new node as non-voting learner to protect leader quorum

### 5. **Learner Promotion (Lines 408-442)**
   - **Old**: Direct `etcdctl member promote` via `delegate_to`
   - **New**: `docker exec {{ _leader }} bash -c '...'`
   - **Retry logic**: Waits 12 attempts × 5 seconds for learner to catch up before promotion

### 6. **Final Health Checks (Lines 463-490)**
   - **Old**: `ansible.builtin.uri` with `delegate_to`
   - **New**: `docker exec {{ _leader }} curl -sf ...` in shell blocks
   - **Validation**: Ensures leader remains healthy after replica joins

### 7. **Rescue Block (Lines 500-571)**
   - **Old**: Direct systemctl/etcd/etcdctl via `delegate_to`
   - **New**: `docker exec {{ _leader }} bash -c '...'` with --force-new-cluster
   - **Purpose**: Recovers leader quorum if replica registration fails

### 8. **Play 3 Cleanup Tasks (Lines 609-702)**
   - **Old**: Direct URI checks and systemctl commands
   - **New**: `docker exec {{ inventory_hostname }}` for all operations
   - **stale members removal**: `docker exec bash -c 'etcdctl member list | awk ...'`
   - **force-new-cluster recovery**: Full inline bash script in `docker exec`

## Technical Patterns Applied

### Pattern 1: Simple Health Checks
```bash
docker exec {{ container }} curl -sf http://127.0.0.1:{{ port }}/{{ endpoint }} \
  >/dev/null 2>&1 && echo "ok" || echo "fail"
```

### Pattern 2: Complex Multi-line Operations
```bash
docker exec {{ container }} bash -c '
  # Multi-line bash script with variables
  # All variables interpolated via {{ ansible_var }}
  # Field separators adjusted: ", " instead of ", " inside bash -c
'
```

### Pattern 3: etcdctl Commands
```bash
docker exec {{ container }} bash -c '
  etcdctl --endpoints=http://127.0.0.1:2379 member list --write-out=simple | \
    awk -F", " "{print \$1}"
'
```

## Testing Recommendations

1. **Uncomment standby replicas** in `hosts.yml`:
   ```yaml
   docpg-cls1-pg5:
     ip: "172.18.0.15"
   docpg-cls1-pg6:
     ip: "172.18.0.16"
   ```

2. **Run playbook**:
   ```bash
   ansible-playbook -i hosts.yml playbook-add-replicas.yml \
     --vault-password-file=vault-pass
   ```

3. **Verify**:
   ```bash
   docker exec docpg-cls1-pg4 patronictl -c /etc/patroni/patroni.yml list
   ```

## Compatibility Notes

- **Group vars**: The new `group_vars/` files (primary_cluster.yml, standby_cluster.yml, etc.) work seamlessly with this updated playbook
- **Docker network**: Uses lab-network (172.18.0.0/16); all endpoints use 127.0.0.1 inside containers
- **Ansible connection**: Requires `community.docker.docker` plugin in hosts.yml

## Files Modified

- ✅ `playbook-add-replicas.yml` — 703 lines (from ~670 lines)
- ✅ Created `group_vars/primary_cluster.yml`
- ✅ Created `group_vars/standby_cluster.yml`
- ✅ Created `group_vars/primary_cluster_replica.yml`
- ✅ Created `group_vars/standby_cluster_replica.yml`
