# playbook-add-replicas.yml — Docker Changes Reference

## Summary

- **Total docker exec calls**: 16
- **Complex bash-c operations**: 6 (etcd cluster calc, member add, learner promote, rescue recovery, cleanup)
- **Simple curl checks**: 10 (health checks)
- **Total lines**: 702 (previous: ~670)

## Change Map

| Section | Old Pattern | New Pattern | Line(s) | Reason |
|---------|------------|------------|---------|--------|
| PREFLIGHT Patroni | `ansible.builtin.uri` | `docker exec curl -sf` | 72-86 | Docker exec required |
| PREFLIGHT PostgreSQL | `ansible.builtin.uri` | `docker exec curl -sf` | 89-100 | Docker exec required |
| PREFLIGHT etcd | `ansible.builtin.uri` | `docker exec curl -sf` | 111-134 | Docker exec required |
| Guard etcd check | `delegate_to` + uri | `docker exec curl -sf` | 243-254 | No delegation needed |
| Guard PG check | `delegate_to` + uri | `docker exec curl -sf` | 256-268 | No delegation needed |
| etcd cluster calc | `delegate_to` + shell | `docker exec bash -c` | 278-302 | Complex script requires docker |
| etcd member add | `delegate_to` + shell | `docker exec bash -c` | 337-365 | Complex script requires docker |
| Learner promote | `delegate_to` + shell | `docker exec bash -c` | 410-442 | Complex script requires docker |
| Final etcd check | `delegate_to` + uri | `docker exec curl -sf` | 466-472 | Docker exec required |
| Final PG check | `delegate_to` + uri | `docker exec curl -sf` | 475-481 | Docker exec required |
| Rescue recovery | `delegate_to` + shell | `docker exec bash -c` | 504-571 | force-new-cluster needs docker |
| Cleanup etcd check | `ansible.builtin.uri` | `docker exec curl -sf` | 609-622 | Docker exec required |
| Cleanup stale removal | `shell` (local) | `docker exec bash -c` | 626-645 | Must run on leader |
| Cleanup recovery | `shell` (local) | `docker exec bash -c` | 649-680 | systemctl/etcd in container |
| Cleanup final check | `ansible.builtin.uri` | `docker exec curl -sf` | 682-695 | Docker exec required |

## Field Separator Handling

**Inside `docker exec ... bash -c '...'`**, field separator changes from `, ` to `, `:

**Before** (direct shell):
```bash
awk -F', ' '{print $1}'
```

**After** (in docker exec bash -c):
```bash
awk -F", " "{print \$1}"
```

This is because Ansible's Jinja2 interpolation handles quotes differently in bash -c context.

## Verification Checklist

- [x] All URI checks converted to docker exec curl
- [x] All delegate_to patterns removed
- [x] Field separators adjusted for bash -c context
- [x] Complex scripts wrapped in `docker exec {{ host }} bash -c '...'`
- [x] Ansible variables ({{ ip }}, {{ _leader }}) properly interpolated
- [x] Group vars files created for variable inheritance
- [x] Syntax validated via grep patterns
- [x] Documentation updated

## Testing Notes

Run with verbose output to verify docker exec calls:
```bash
ansible-playbook -i hosts.yml playbook-add-replicas.yml \
  --vault-password-file=vault-pass -vvv 2>&1 | grep "docker exec"
```

Monitor container logs during execution:
```bash
docker logs -f docpg-cls1-pg4 2>&1 | grep -E "etcd|ERROR"
```
