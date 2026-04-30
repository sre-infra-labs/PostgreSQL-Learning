# Docker-Based PostgreSQL 18 HA Cluster
## Patroni + etcd + pgBackRest + pgBouncer + HAProxy + Keepalived + pg_exporter

---

## Architecture

Every pg container runs the full stack — PostgreSQL, Patroni, etcd, pgBouncer, HAProxy, and
Keepalived — in a single privileged container. There is no separate proxy or DCS container.

```
Host (macOS)
│
├── Docker Network: lab-network (172.18.0.0/16)
│   │
│   ├── 172.18.0.9  ← Keepalived Replica VIP  (floats to the highest-priority healthy replica)
│   ├── 172.18.0.10 ← Keepalived Primary VIP  (floats to the Patroni leader)
│   │
│   ├── pg1  (172.18.0.11)  — PostgreSQL 18 + Patroni + etcd + pgBouncer + HAProxy + Keepalived
│   ├── pg2  (172.18.0.12)  — PostgreSQL 18 + Patroni + etcd + pgBouncer + HAProxy + Keepalived
│   └── pg3  (172.18.0.13)  — PostgreSQL 18 + Patroni + etcd + pgBouncer + HAProxy + Keepalived
│
└── Docker Named Volume: pg-backups  (shared pgBackRest POSIX repo)
```

### Port Mapping (host → container)

```
┌──────────┬──────┬──────┬─────────┬─────────────┬──────────┬───────────────────────────────────┐
│ Container│ SSH  │ PG   │ Patroni │ pg_exporter │ pgBouncer│ HAProxy (host ports — needs new    │
│          │      │      │ REST    │             │          │  container creation to take effect) │
├──────────┼──────┼──────┼─────────┼─────────────┼──────────┼────────┬──────────┬───────────────┤
│ pg1      │ 2221 │ 5433 │ 8011    │ 9194        │ 6433     │ 15000  │ 15001    │ 17000         │
│ pg2      │ 2222 │ 5434 │ 8012    │ 9195        │ 6434     │ 25000  │ 25001    │ 27000         │
│ pg3      │ 2223 │ 5435 │ 8013    │ 9196        │ 6435     │ 35000  │ 35001    │ 37000         │
└──────────┴──────┴──────┴─────────┴─────────────┴──────────┴────────┴──────────┴───────────────┘
                                                              write    read      stats
                                                              port     port      UI

HAProxy container-internal ports (always available via docker exec):
  :5000 → write   (routes to Patroni primary only, health: GET /primary  → 200)
  :5001 → read    (routes to healthy replicas,     health: GET /replica  → 200)
  :7000 → stats   (HTTP UI, basic auth: admin / <PG_SUPERUSER_PWD>)

etcd cluster (inter-container, no host port mapping needed):
  pg1: 172.18.0.11:2379 (client) / :2380 (peer)
  pg2: 172.18.0.12:2379 (client) / :2380 (peer)
  pg3: 172.18.0.13:2379 (client) / :2380 (peer)
```

### Traffic Flow

```
Application write  →  VIP 172.18.0.10:5000  →  HAProxy (any node)  →  pg2 :5432 (leader)
Application read   →  VIP 172.18.0.10:5001  →  HAProxy (any node)  →  pg1/pg3 :5432 (replicas)

After failover (e.g. pg1 becomes new leader):
  Keepalived detects /primary passes on pg1 → VIP migrates to pg1
  HAProxy health checks catch up within 6–9 s (3 × inter=3s)
```

---

## Component Stack

| Component        | Version   | Role                                             |
|------------------|-----------|--------------------------------------------------|
| PostgreSQL       | 18 (PGDG) | Database engine                                  |
| Patroni          | 4.0.6     | HADR orchestration (automatic failover)          |
| etcd             | 3.5.17    | DCS — distributed configuration store           |
| pgBackRest       | latest    | Backup & restore (POSIX shared volume)           |
| pgBouncer        | latest    | Connection pooler per node                       |
| HAProxy          | 2.8.x     | TCP proxy with Patroni API health checks         |
| Keepalived       | 2.2.x     | VRRP VIP management (unicast, no multicast)      |
| pg_exporter      | 0.17.1    | Prometheus metrics                               |
| pg_wait_tracer   | main      | Wait event tracing (compiled from source)        |

---

## Connecting to PostgreSQL

### A. Direct connections (always available from Mac host)

```bash
export PGPASSWORD='Pg@Lab2026!'

# pg1 (usually replica)
psql -h localhost -p 5433 -U postgres -d postgres

# pg2 (usually leader)
psql -h localhost -p 5434 -U postgres -d postgres

# pg3 (usually replica)
psql -h localhost -p 5435 -U postgres -d postgres

# Check which node is the leader
psql -h localhost -p 5433 -U postgres -d postgres -c "SELECT pg_is_in_recovery();"
# f = primary (leader), t = replica (standby)
```

### B. Via pgBouncer on each node (always available from Mac host)

pgBouncer routes to local PostgreSQL. Since Patroni callback updates the target on role-change,
each pgBouncer stays pointed at `127.0.0.1:5432` (its own node).

```bash
export PGPASSWORD='Pg@Lab2026!'

psql -h localhost -p 6433 -U postgres -d postgres   # pgBouncer on pg1 → pg1
psql -h localhost -p 6434 -U postgres -d postgres   # pgBouncer on pg2 → pg2 (leader)
psql -h localhost -p 6435 -U postgres -d postgres   # pgBouncer on pg3 → pg3
```

### C. Via Keepalived VIPs (available inside Docker network / container exec)

The VIPs float between containers — clients always reach the right node without knowing
which physical container currently holds the role.

```bash
# Primary VIP → always reaches the Patroni leader
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5432 -U postgres -d postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# Replica VIP → reaches the highest-priority healthy replica (pg1 when available)
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.9 -p 5432 -U postgres -d postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
```

### D. Via HAProxy + Keepalived VIP (best practice — inside Docker network)

Combine both: use Keepalived VIP to reach a node's HAProxy, then HAProxy routes to the
correct backend based on the Patroni health check. This is fully transparent to the application.

```bash
# Writes (primary only) — HAProxy verifies via GET /primary → 200
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 -U postgres -d postgres \
  -c "SELECT inet_server_addr() AS server, pg_is_in_recovery() AS is_replica;"'
# Result: server=172.18.0.12, is_replica=f  ← always the leader

# Reads (replicas only) — HAProxy verifies via GET /replica → 200
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5001 -U postgres -d postgres \
  -c "SELECT inet_server_addr() AS server, pg_is_in_recovery() AS is_replica;"'
# Result: server=172.18.0.11, is_replica=t  ← a replica (round-robins across healthy replicas)

# Using replica VIP + HAProxy read port
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.9 -p 5001 -U postgres -d postgres \
  -c "SELECT inet_server_addr() AS server, pg_is_in_recovery() AS is_replica;"'
```

### E. Via HAProxy host-mapped ports (requires container recreation)

The HAProxy host-port mappings (15000, 25000, 35000 etc.) were added AFTER the current
containers were created. To expose them to the Mac host, recreate the containers:

```bash
# WARNING: recreating containers preserves data volumes but resets container state
ansible-playbook playbook-setup-docker.yml    # recreates containers with new port mappings
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true -e skip_confirm=true

# After recreation — HAProxy directly from Mac host (via any node's host port):
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -p 25000 -U postgres -d postgres   # pg2 HAProxy write port → primary
psql -h localhost -p 15001 -U postgres -d postgres   # pg1 HAProxy read port  → replica
```

---

## Patroni Status & Management

```bash
# Full cluster status (run from any node)
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list

# Cluster topology with history
docker exec pg2 patronictl -c /etc/patroni/patroni.yml topology

# Replication lag check
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list | grep -E "Lag|Member"

# Show current cluster config (DCS-stored parameters)
docker exec pg2 patronictl -c /etc/patroni/patroni.yml show-config

# Edit DCS-stored cluster config
docker exec pg2 patronictl -c /etc/patroni/patroni.yml edit-config

# Patroni REST API — health check on each node
curl -s http://localhost:8011/patroni | python3 -m json.tool   # pg1
curl -s http://localhost:8012/patroni | python3 -m json.tool   # pg2
curl -s http://localhost:8013/patroni | python3 -m json.tool   # pg3

# Check which node is primary (returns HTTP 200 only on primary)
curl -s -o /dev/null -w "%{http_code}" http://localhost:8011/primary   # 503 if replica
curl -s -o /dev/null -w "%{http_code}" http://localhost:8012/primary   # 200 if leader
curl -s -o /dev/null -w "%{http_code}" http://localhost:8013/primary   # 503 if replica

# Check which nodes are healthy replicas
curl -s -o /dev/null -w "%{http_code}" http://localhost:8011/replica   # 200 if streaming replica
curl -s -o /dev/null -w "%{http_code}" http://localhost:8013/replica   # 200 if streaming replica

# Trigger a manual failover (promotes a replica to leader)
docker exec pg2 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force

# Failover to a specific node
docker exec pg2 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 \
  --master pg2 --candidate pg1 --force

# Switchover (graceful, requires a leader)
docker exec pg2 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 --force

# Pause/resume Patroni automatic failover
docker exec pg2 patronictl -c /etc/patroni/patroni.yml pause
docker exec pg2 patronictl -c /etc/patroni/patroni.yml resume

# Reload Patroni config after editing patroni.yml
docker exec pg2 patronictl -c /etc/patroni/patroni.yml reload pg-docker-cls1

# Reinitialize a lagging/diverged replica
docker exec pg2 patronictl -c /etc/patroni/patroni.yml reinit pg-docker-cls1 pg1 --force
```

---

## PostgreSQL Status

```bash
export PGPASSWORD='Pg@Lab2026!'

# Connect to specific node
psql -h localhost -p 5433 -U postgres postgres   # pg1
psql -h localhost -p 5434 -U postgres postgres   # pg2 (usually leader)
psql -h localhost -p 5435 -U postgres postgres   # pg3

# Replication status (run on primary)
psql -h localhost -p 5434 -U postgres postgres -c "
  SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
         (sent_lsn - replay_lsn) AS replication_lag_bytes
  FROM pg_stat_replication;"

# Replication lag in MB (run on primary)
psql -h localhost -p 5434 -U postgres postgres -c "
  SELECT client_addr,
         round((sent_lsn - replay_lsn) / 1048576.0, 2) AS lag_mb
  FROM pg_stat_replication;"

# Check standby recovery status (run on replica)
psql -h localhost -p 5433 -U postgres postgres -c "
  SELECT now() - pg_last_xact_replay_timestamp() AS replication_delay,
         pg_is_in_recovery(), pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();"

# Active connections and sessions
psql -h localhost -p 5434 -U postgres postgres -c "
  SELECT count(*), state, wait_event_type, wait_event
  FROM pg_stat_activity GROUP BY state, wait_event_type, wait_event ORDER BY count DESC;"

# Long-running queries (>30s)
psql -h localhost -p 5434 -U postgres postgres -c "
  SELECT pid, now()-query_start AS duration, state, left(query,80) AS query
  FROM pg_stat_activity
  WHERE state != 'idle' AND query_start < now() - interval '30 seconds'
  ORDER BY duration DESC;"

# pg_stat_statements top 10 by total time
psql -h localhost -p 5434 -U postgres postgres -c "
  SELECT round(total_exec_time::numeric,2) AS total_ms,
         calls, round(mean_exec_time::numeric,2) AS mean_ms,
         left(query,80) AS query
  FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;"

# Database sizes
psql -h localhost -p 5434 -U postgres postgres -c "
  SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY 2 DESC;"

# Table bloat (top 10)
psql -h localhost -p 5434 -U postgres postgres -c "
  SELECT schemaname, tablename,
         pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
         n_dead_tup, n_live_tup
  FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10;"
```

---

## HAProxy Status & Management

```bash
# HAProxy backend health summary (CSV stats from inside a container)
docker exec pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep -v "^#" | cut -d, -f1,2,18 | column -t -s,'

# Full stats page (open in browser after port-forwarding)
# From inside container: http://172.18.0.12:7000/  (admin / <PG_SUPERUSER_PWD>)

# Check which backends are UP (for write port)
docker exec pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep "be_write" | cut -d, -f1,2,18'

# Check which backends are UP (for read port)
docker exec pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep "be_read" | cut -d, -f1,2,18'

# HAProxy service status on each node
for n in pg1 pg2 pg3; do
  echo "=== $n ==="; docker exec $n systemctl status haproxy --no-pager -l | tail -3
done

# Reload HAProxy config (no connection drops, used after config change)
for n in pg1 pg2 pg3; do docker exec $n systemctl reload haproxy; done

# Verify HAProxy write port routes only to primary
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres -d postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# Verify HAProxy read port routes only to replica
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5001 \
  -U postgres -d postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'
```

---

## Keepalived Status & Management

```bash
# Which node holds each VIP
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n ip addr show eth0 | grep "inet "
done
# 172.18.0.10 (eth0:vip)    → Patroni primary
# 172.18.0.9  (eth0:rvip)   → highest-priority healthy replica

# Keepalived service status
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n systemctl status keepalived --no-pager | tail -5
done

# VRRP state on each node (MASTER vs BACKUP)
for n in pg1 pg2 pg3; do
  echo -n "$n: "
  docker exec $n journalctl -u keepalived --no-pager -n 5 2>/dev/null \
    | grep -E "MASTER|BACKUP" | tail -2
done

# Keepalived effective priorities (shows weight contribution)
for n in pg1 pg2 pg3; do
  echo -n "$n primary check: "
  docker exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary
  echo -n "  replica check: "
  docker exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/replica
  echo
done

# Manually verify VIP reachability from inside cluster
docker exec pg3 ping -c 2 172.18.0.10   # primary VIP
docker exec pg3 ping -c 2 172.18.0.9    # replica VIP

# Restart Keepalived (re-triggers VRRP election)
for n in pg1 pg2 pg3; do docker exec $n systemctl restart keepalived; done
# Wait ~8s for election to settle then re-check VIP assignment
```

---

## pgBouncer Status & Management

```bash
# pgBouncer admin console (from Mac host via mapped port)
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -p 6433 -U postgres pgbouncer -c "SHOW POOLS;"    # pg1
psql -h localhost -p 6434 -U postgres pgbouncer -c "SHOW POOLS;"    # pg2
psql -h localhost -p 6435 -U postgres pgbouncer -c "SHOW POOLS;"    # pg3

# All useful pgBouncer admin commands
psql -h localhost -p 6434 -U postgres pgbouncer << 'EOF'
SHOW CLIENTS;
SHOW SERVERS;
SHOW STATS;
SHOW POOLS;
SHOW DATABASES;
SHOW CONFIG;
EOF

# pgBouncer service status
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n systemctl status pgbouncer --no-pager | tail -3
done

# Reload pgBouncer after config change
for n in pg1 pg2 pg3; do docker exec $n systemctl reload pgbouncer; done

# Fix stale connection pool (SASL auth failures after failover)
# This clears all server-side connections and forces reconnects
for n in pg1 pg2 pg3; do
  echo "Reconnecting $n pgBouncer pools..."
  docker exec $n bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 127.0.0.1 -p 6432 \
    -U postgres pgbouncer -c "RECONNECT;" 2>/dev/null' \
  || docker exec $n systemctl reload pgbouncer
done

# Check which PostgreSQL host each pgBouncer is pointing to
for n in pg1 pg2 pg3; do
  echo -n "$n pgbouncer → " && docker exec $n grep "^*" /etc/pgbouncer/pgbouncer.ini
done
```

---

## etcd Status & Management

```bash
# etcd cluster member list (from inside container)
docker exec pg1 etcdctl --endpoints=http://172.18.0.11:2379 member list

# etcd cluster health
docker exec pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health

# etcd endpoint status (leader, raft term, raft index)
docker exec pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint status --write-out=table

# Read Patroni DCS key
docker exec pg1 etcdctl --endpoints=http://172.18.0.11:2379 \
  get /service/pg-docker-cls1/leader

# etcd service status
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n systemctl status etcd --no-pager | tail -3
done
```

---

## pgBackRest Status & Management

```bash
# Show backup info (run from any node with access to shared volume)
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 info

# Full backup (run on leader)
docker exec pg2 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info backup --type=full

# Incremental backup
docker exec pg2 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info backup --type=incr

# Differential backup
docker exec pg2 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info backup --type=diff

# Check backup integrity
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 check

# Restore (stop patroni first, then restore, then restart)
docker exec pg2 systemctl stop patroni
docker exec pg2 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info restore --delta
docker exec pg2 systemctl start patroni

# Point-in-time restore
docker exec pg2 systemctl stop patroni
docker exec pg2 pgbackrest --stanza=pg-docker-cls1 --log-level-console=info restore --delta \
  --target="2026-04-30 10:30:00" --target-action=promote
docker exec pg2 systemctl start patroni
```

---

## Log Inspection

All commands use `docker exec` so they work from the Mac host terminal without SSH.

### PostgreSQL logs

```bash
# Tail PostgreSQL log on the current leader (pg2)
docker exec pg2 tail -100 /var/log/postgresql/postgresql-Wed.log

# Follow PostgreSQL log live
docker exec pg2 bash -c "tail -f /var/log/postgresql/postgresql-$(date +%a).log"

# Search for errors in PostgreSQL log
docker exec pg2 grep -i "ERROR\|FATAL\|PANIC" /var/log/postgresql/postgresql-Wed.log | tail -20

# PostgreSQL log on all nodes
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n bash -c \
    "tail -20 /var/log/postgresql/postgresql-\$(date +%a).log 2>/dev/null || echo 'no log'"
done
```

### Patroni logs

```bash
# Patroni log on all nodes
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n tail -30 /var/log/patroni/patroni.log
done

# Follow Patroni log live on leader
docker exec pg2 tail -f /var/log/patroni/patroni.log

# Patroni log via journald
docker exec pg2 journalctl -u patroni --no-pager -n 50

# Search for failover/switchover events
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n grep -i "promoting\|demoting\|failover\|switchover\|leader" \
    /var/log/patroni/patroni.log | tail -10
done
```

### HAProxy logs

```bash
# HAProxy logs via journald
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u haproxy --no-pager -n 20
done

# Follow HAProxy log live
docker exec pg2 journalctl -u haproxy -f

# Check backend state changes in HAProxy log
docker exec pg2 journalctl -u haproxy --no-pager | grep -i "UP\|DOWN\|BACKEND"
```

### Keepalived logs

```bash
# Keepalived VRRP election and VIP assignment events
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u keepalived --no-pager -n 20
done

# Follow Keepalived log live (watch VIP migrations)
docker exec pg2 journalctl -u keepalived -f

# Show only MASTER/BACKUP transitions
for n in pg1 pg2 pg3; do
  echo -n "$n: " && docker exec $n journalctl -u keepalived --no-pager \
    | grep -E "MASTER STATE|BACKUP STATE" | tail -3
done
```

### pgBouncer logs

```bash
# pgBouncer log on all nodes
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n tail -20 /var/log/pgbouncer/pgbouncer.log
done

# Follow pgBouncer log live
docker exec pg2 tail -f /var/log/pgbouncer/pgbouncer.log

# Search for auth errors
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n grep -i "ERROR\|failed\|refused" \
    /var/log/pgbouncer/pgbouncer.log | tail -5
done
```

### pgBackRest logs

```bash
# pgBackRest log
docker exec pg1 cat /var/log/pgbackrest/pg-docker-cls1-backup.log 2>/dev/null | tail -30
docker exec pg1 ls /var/log/pgbackrest/
```

### etcd logs

```bash
# etcd logs via journald
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u etcd --no-pager -n 15
done

# etcd leader election events
for n in pg1 pg2 pg3; do
  echo "=== $n ===" && docker exec $n journalctl -u etcd --no-pager \
    | grep -i "elected\|leader\|follower" | tail -5
done
```

---

## Health Validation Cheatsheet

```bash
export PGPASSWORD='Pg@Lab2026!'

# 1. Patroni cluster state
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list

# 2. VIP locations
for n in pg1 pg2 pg3; do
  echo -n "$n: " && docker exec $n ip addr show eth0 | grep "inet " | awk '{print $2}'
done

# 3. HAProxy backend health (1 line per backend)
docker exec pg2 bash -c \
  'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
   | grep -v "^#\|FRONTEND" | cut -d, -f1,2,18'

# 4. Write path: confirm connection lands on primary
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# 5. Read path: confirm connection lands on a replica
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5001 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# 6. All direct PG ports
for port in 5433 5434 5435; do
  echo -n "localhost:$port → "
  psql -h localhost -p $port -U postgres postgres -c "SELECT pg_is_in_recovery();" -t 2>&1 | tr -d ' \n'
  echo
done

# 7. All pgBouncer ports
for port in 6433 6434 6435; do
  echo -n "localhost:$port → "
  psql -h localhost -p $port -U postgres postgres -c "SELECT pg_is_in_recovery();" -t 2>&1 | tr -d ' \n'
  echo
done

# 8. etcd health
docker exec pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
  endpoint health

# 9. pgBackRest stanza check
docker exec pg1 pgbackrest --stanza=pg-docker-cls1 check
```

---

## Failover Testing

```bash
export PGPASSWORD='Pg@Lab2026!'

# Before failover: note current leader and VIP holder
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list
docker exec pg2 ip addr show eth0 | grep "inet "

# Trigger failover
docker exec pg2 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force

# Watch VIP migrate (run in a second terminal, re-runs every 2s)
watch -n 2 'for n in pg1 pg2 pg3; do echo -n "$n: "; docker exec $n ip addr show eth0 | grep "inet " | awk "{print \$2}"; done'

# Verify write connection lands on new leader (HAProxy updates within ~9s)
sleep 10
docker exec pg3 bash -c 'PGPASSWORD="Pg@Lab2026!" psql -h 172.18.0.10 -p 5000 \
  -U postgres postgres -c "SELECT inet_server_addr(), pg_is_in_recovery();"'

# Simulate node failure (stop pg2)
docker stop pg2
sleep 15
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list   # new leader elected

# Recover failed node
docker start pg2
sleep 20
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list   # pg2 rejoins as replica
```

---

## Troubleshooting

### pgBouncer SASL authentication failed

Symptom: `FATAL: SASL authentication failed` when connecting through pgBouncer.

Cause: Stale server-side pool connections (common after a Patroni failover/restart).

```bash
# Fix: reload pgBouncer to clear stale connections
for n in pg1 pg2 pg3; do docker exec $n systemctl reload pgbouncer; done
```

### Keepalived VIP not assigned (silent failure)

Symptom: `ip addr show eth0` shows no VIP despite Keepalived running.

Common cause: Interface label too long (Linux limit: 15 chars). Check the log:

```bash
docker exec pg1 journalctl -u keepalived --no-pager | grep -i "label\|removing\|no VIP"
```

Fix: Ensure labels in `keepalived.conf.j2` are ≤15 chars (e.g., `eth0:vip`, `eth0:rvip`).

### HAProxy backend shows all DOWN

Symptom: All backends DOWN in `be_write` or `be_read`.

```bash
# Check if Patroni REST API is reachable
for n in pg1 pg2 pg3; do
  echo -n "$n /primary: "
  docker exec $n curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8008/primary
  echo
done

# Restart HAProxy if needed
for n in pg1 pg2 pg3; do docker exec $n systemctl restart haproxy; done
```

### Patroni failover not happening

```bash
# Check if Patroni is paused
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list | grep -i pause

# Resume if paused
docker exec pg2 patronictl -c /etc/patroni/patroni.yml resume

# Check etcd connectivity (DCS required for failover)
docker exec pg2 etcdctl --endpoints=http://172.18.0.12:2379 endpoint health
```

### Replica lagging behind

```bash
# Check lag
docker exec pg2 patronictl -c /etc/patroni/patroni.yml list

# Reinitialize lagging replica from scratch
docker exec pg2 patronictl -c /etc/patroni/patroni.yml reinit pg-docker-cls1 pg3 --force
```

### Container won't start after Docker Desktop restart

```bash
docker start pg1 pg2 pg3
sleep 5
# Services (patroni, etcd, pgbouncer, haproxy, keepalived) are enabled and auto-start
docker exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

### etcd quorum lost (2 of 3 nodes down)

The cluster becomes read-only (no Patroni operations). Restart at least 2 nodes:

```bash
docker start pg1 pg2
sleep 10
docker exec pg1 etcdctl \
  --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379 \
  endpoint health
```

---

## Common Ansible Operations

```bash
cd playbook-install-pg-cluster-docker/

# Full cluster install (Phase 1 + Phase 2)
ansible-playbook playbook-setup-docker.yml
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml --vault-password-file=vault-pass

# Install/reconfigure a single component only
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags haproxy
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags keepalived
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags haproxy,keepalived
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags patroni
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags pgbouncer
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags pgbackrest
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass --tags etcd

# Reinitialize cluster (DESTROYS ALL DATA — keeps packages)
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true

# Reinitialize without confirmation prompt (CI/automation)
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass -e reinit_cluster=true -e skip_confirm=true

# Reinitialize + wipe all pgBackRest backups
ansible-playbook -i hosts.yml playbook-install-pg-cluster.yml \
  --vault-password-file=vault-pass \
  -e reinit_cluster=true -e skip_confirm=true -e cleanup_pgbackrest_backups=true

# Edit vault credentials
ansible-vault edit sensitive-values --vault-password-file=vault-pass

# SSH into containers
ssh -i ~/.ssh/id_ed25519 -p 2221 -o StrictHostKeyChecking=no ansible@127.0.0.1   # pg1
ssh -i ~/.ssh/id_ed25519 -p 2222 -o StrictHostKeyChecking=no ansible@127.0.0.1   # pg2
ssh -i ~/.ssh/id_ed25519 -p 2223 -o StrictHostKeyChecking=no ansible@127.0.0.1   # pg3

# Stop/start all pg containers
docker stop pg1 pg2 pg3 && docker start pg1 pg2 pg3

# Full teardown — WARNING: destroys all data
docker rm -f pg1 pg2 pg3
docker volume rm pg-data-pg1 pg-data-pg2 pg-data-pg3 \
                 pg-logs-pg1 pg-logs-pg2 pg-logs-pg3 pg-backups
```

---

## Prometheus Scrape Config

```yaml
scrape_configs:
  - job_name: postgresql_docker
    static_configs:
      - targets:
          - 'host.docker.internal:9194'   # pg1
          - 'host.docker.internal:9195'   # pg2
          - 'host.docker.internal:9196'   # pg3
        labels:
          cluster: pg-docker-cls1
          env: docker-local

# Reload Prometheus after editing
# curl -X POST http://localhost:9090/-/reload
```

---

## Design Notes

- **No shared proxy container**: HAProxy + Keepalived run on every pg container. The VIP floats
  to the right node — no SPOF proxy tier. All 3 nodes can handle the write path if the VIP moves.

- **Keepalived unicast mode**: Docker bridge networks don't reliably support multicast (needed by
  default VRRP). We configure `unicast_src_ip` / `unicast_peer` to route VRRP advertisements
  directly between container IPs.

- **VIP weight logic**: `vrrp_script` adds +100 to the base priority (101/100/99) when the health
  check passes. Primary node effective priority: 201/200/199. Replicas: 101/100/99. Guarantees the
  primary always holds the primary VIP, and no node holds both VIPs simultaneously.

- **pgBouncer `auth_type = scram-sha-256`**: Plain text passwords in `userlist.txt` are supported
  by pgBouncer 1.16+ for SCRAM authentication. After Patroni failovers, reload pgBouncer to clear
  stale server-side connections (`systemctl reload pgbouncer`).

- **HAProxy host ports**: The HAProxy host-port mappings (15000/25001/17000 etc.) were added to
  container definitions in `roles/docker_infrastructure/defaults/main.yml` but only take effect
  when containers are recreated. The container-internal ports (5000/5001/7000) are always active.

- **Passwords**: must NOT contain `$` (PostgreSQL dollar-quote delimiter breaks Patroni post-bootstrap SQL).

- **pgBackRest stanza**: created once on the leader. All nodes share the same POSIX repo via the
  `pg-backups` Docker named volume mounted at `/var/lib/pgbackrest`.
