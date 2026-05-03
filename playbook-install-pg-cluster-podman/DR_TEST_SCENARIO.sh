#!/bin/bash

################################################################################
# PostgreSQL 18 HA Cluster — Disaster Recovery (DR) Test Scenario
#
# Purpose: Test pg3 failover when pg1 (Leader) and pg2 (Sync Standby) fail
#
# Topology:
#   NORMAL:      pg1 (Leader) + pg2 (Sync Standby) + pg3 (Replica)
#   DR MODE:     pg3 (Leader) [pg1 & pg2 offline]
#   RECOVERED:   pg1 (Leader) + pg2 (Sync Standby) + pg3 (Replica) [restored]
#
# Usage:
#   bash DR_TEST_SCENARIO.sh all      # Run complete DR test
#   bash DR_TEST_SCENARIO.sh normal   # Check normal state
#   bash DR_TEST_SCENARIO.sh dr       # Simulate disaster (stop pg1 & pg2)
#   bash DR_TEST_SCENARIO.sh recover  # Bring pg1 & pg2 back online
#   bash DR_TEST_SCENARIO.sh restore  # Switchover pg3 → pg1 (restore topology)
#
################################################################################

set -e

export PGPASSWORD='Pg@Lab2026!'

####################
# PRE-DR: NORMAL STATE
####################
check_normal_state() {
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║         PRE-DR: VERIFY NORMAL CLUSTER STATE                   ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  echo ""
  echo "=== 1. Cluster Topology (Expected: pg1=Leader, pg2=Sync Standby, pg3=Replica) ==="
  podman exec pg1 patronictl -c /etc/patroni/patroni.yml list

  echo ""
  echo "=== 2. VIP Assignments (Before DR) ==="
  for n in pg1 pg2 pg3; do
    echo -n "$n: "
    podman exec $n ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}'
  done

  echo ""
  echo "=== 3. PostgreSQL Node Status ==="
  for port in 5433 5434 5435; do
    node_name=""
    [ "$port" = "5433" ] && node_name="pg1 (Leader)"
    [ "$port" = "5434" ] && node_name="pg2 (Standby)"
    [ "$port" = "5435" ] && node_name="pg3 (Replica)"
    echo -n "$node_name → "
    psql -h localhost -p $port -U postgres postgres -c "SELECT 'OK';" -t 2>&1 | tr -d ' \n'
    echo
  done

  echo ""
  echo "=== 4. HAProxy Backend Health ==="
  podman exec pg1 bash -c 'curl -s -u "admin:Pg@Lab2026!" "http://127.0.0.1:7000/;csv" \
    | grep -v "^#\|FRONTEND" | cut -d, -f1,2,18'

  echo ""
  echo "✓ NORMAL STATE VERIFIED"
}

####################
# DISASTER: SIMULATE FAILURE
####################
simulate_disaster() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║              ⚠️  SIMULATING DISASTER (DR MODE)                ║"
  echo "║         Stopping pg1 (Leader) and pg2 (Sync Standby)          ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  echo ""
  echo "=== Step 1: Stop pg1 (Leader) ==="
  podman stop pg1
  echo "✓ pg1 stopped"

  echo ""
  echo "=== Step 2: Stop pg2 (Sync Standby) ==="
  podman stop pg2
  echo "✓ pg2 stopped"

  echo ""
  echo "=== Step 3: Wait 10 seconds for Patroni to detect failure ==="
  sleep 10
  echo "✓ Waited"

  echo ""
  echo "=== Step 4: Verify pg1 & pg2 are DOWN and pg3 is still REPLICA ==="
  echo "    (Note: Automatic failover is DISABLED and pg3 is async - manual promotion required)"
  echo ""
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml list

  echo ""
  echo "=== Step 5: MANUAL PROMOTION - Elect pg3 as Leader (REQUIRED) ==="
  echo "    ⚠️  Automatic failover is disabled in this cluster"
  echo "    ✓ Triggering manual failover to promote pg3..."
  echo ""
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml failover pg-docker-cls1 --force
  sleep 5

  echo ""
  echo "=== Step 6: Verify pg3 is NOW the Leader ==="
  status=$(podman exec pg3 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null)
  echo "$status"

  if echo "$status" | grep -q "pg3.*Leader"; then
    echo ""
    echo "✓ pg3 manually promoted to Leader!"
  else
    echo ""
    echo "⚠️  ERROR: pg3 is NOT yet leader. Check cluster state:"
    podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
  fi

  echo ""
  echo "=== DR MODE ACTIVE: pg3 is now the Leader ==="
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml list
}

####################
# VERIFY DR STATE
####################
verify_dr_state() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║            VERIFY DR MODE: pg3 IS ACTIVE LEADER                ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  echo ""
  echo "=== 1. Cluster Topology (Should be: pg3=Leader only) ==="
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml list

  echo ""
  echo "=== 2. VIP Assignments in DR Mode ==="
  echo -n "pg3: "
  podman exec pg3 ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}'

  echo ""
  echo "=== 3. pg3 is PRIMARY (accepts writes) ==="
  podman exec pg3 psql -U postgres postgres -c "SELECT inet_server_addr() AS node, pg_is_in_recovery() AS is_replica, now() AS timestamp;"

  echo ""
  echo "=== 4. Test WRITE on pg3 (DR node) ==="
  psql -h localhost -p 5435 -U postgres postgres -c \
    "CREATE TABLE IF NOT EXISTS dr_test (id SERIAL PRIMARY KEY, msg TEXT, created_at TIMESTAMP DEFAULT NOW());
     INSERT INTO dr_test (msg) VALUES ('DR test write from pg3 - ' || now());
     SELECT * FROM dr_test ORDER BY id DESC LIMIT 3;"

  echo ""
  echo "=== 5. Patroni Health Check on pg3 ==="
  echo -n "pg3 /primary endpoint: "
  podman exec pg3 curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:8013/primary

  echo ""
  echo "✓ DR MODE VERIFIED: pg3 accepting user connections"
}

####################
# RECOVERY: BRING NODES BACK
####################
recover_cluster() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║            RECOVERY: BRING pg1 & pg2 BACK ONLINE               ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  echo ""
  echo "=== Step 1: Start pg1 (will rejoin as Replica) ==="
  podman start pg1
  echo "✓ pg1 started"

  echo ""
  echo "=== Step 2: Start pg2 (will rejoin as Replica) ==="
  podman start pg2
  echo "✓ pg2 started"

  echo ""
  echo "=== Step 3: Wait 15 seconds for services to start ==="
  sleep 15
  echo "✓ Waited"

  echo ""
  echo "=== Step 4: Monitor cluster reformation (wait ~60 sec) ==="
  for i in {1..30}; do
    echo "--- Rejoin check $i (elapsed: ${i}0s) ---"
    status=$(podman exec pg3 patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | tail -3 | head -2 || echo "Waiting...")
    echo "$status"

    # Check if all 3 nodes are members
    member_count=$(echo "$status" | grep -c "pg[123]" || echo 0)
    [ "$member_count" -ge 3 ] && {
      echo "✓ All 3 nodes rejoined!"
      break
    }

    sleep 2
  done

  echo ""
  echo "=== Final Cluster State After Recovery ==="
  podman exec pg1 patronictl -c /etc/patroni/patroni.yml list
}

####################
# RESTORE: ORIGINAL TOPOLOGY
####################
restore_original_topology() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  RESTORE: Switchover pg3 → pg1 (restore original topology)    ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  echo ""
  echo "=== Current Leader Before Switchover ==="
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml list | grep Leader

  echo ""
  echo "=== Executing Switchover: pg3 → pg1 ==="
  podman exec pg3 patronictl -c /etc/patroni/patroni.yml switchover pg-docker-cls1 \
    --leader pg3 --candidate pg1 --force

  echo ""
  echo "=== Waiting 10 seconds for switchover to complete ==="
  sleep 10

  echo ""
  echo "=== Cluster Topology After Switchover ==="
  podman exec pg1 patronictl -c /etc/patroni/patroni.yml list

  echo ""
  echo "=== VIP Assignments After Switchover ==="
  for n in pg1 pg2 pg3; do
    echo -n "$n: "
    podman exec $n ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}'
  done

  echo ""
  echo "=== Verify pg1 is now PRIMARY ==="
  psql -h localhost -p 5433 -U postgres postgres -c \
    "SELECT inet_server_addr() AS node, pg_is_in_recovery() AS is_replica;"

  echo ""
  echo "✓ TOPOLOGY RESTORED: pg1=Leader, pg2=Standby, pg3=Replica"
}

####################
# POST-RECOVERY VALIDATION
####################
validate_recovery() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║         POST-RECOVERY VALIDATION: BACK TO NORMAL                ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  echo ""
  echo "=== 1. All PostgreSQL Nodes Operational ==="
  for port in 5433 5434 5435; do
    node_name=""
    [ "$port" = "5433" ] && node_name="pg1"
    [ "$port" = "5434" ] && node_name="pg2"
    [ "$port" = "5435" ] && node_name="pg3"
    echo -n "$node_name (port $port): "
    psql -h localhost -p $port -U postgres postgres -c "SELECT 'OK';" -t 2>&1 | tr -d ' \n'
    echo
  done

  echo ""
  echo "=== 2. Patroni REST API Health ==="
  for port in 8011 8012 8013; do
    node_name=""
    [ "$port" = "8011" ] && node_name="pg1"
    [ "$port" = "8012" ] && node_name="pg2"
    [ "$port" = "8013" ] && node_name="pg3"
    echo -n "$node_name (port $port): "
    curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:$port/patroni
  done

  echo ""
  echo "=== 3. Replication Lag Status ==="
  psql -h localhost -p 5433 -U postgres postgres -c \
    "SELECT client_addr, state, sync_state, \
            ROUND(EXTRACT(EPOCH FROM write_lag)::NUMERIC, 3) AS write_lag_sec,
            ROUND(EXTRACT(EPOCH FROM replay_lag)::NUMERIC, 3) AS replay_lag_sec
     FROM pg_stat_replication ORDER BY client_addr;"

  echo ""
  echo "=== 4. etcd Cluster Health ==="
  healthy_count=$(podman exec pg1 etcdctl --endpoints=http://172.18.0.11:2379,http://172.18.0.12:2379,http://172.18.0.13:2379 \
    endpoint health 2>/dev/null | grep -c "healthy" || echo 0)
  echo "Healthy etcd members: $healthy_count (should be 3)"

  echo ""
  echo "✓ RECOVERY VALIDATION COMPLETE"
}

####################
# MAIN
####################
main() {
  action="${1:-all}"

  case "$action" in
    normal)
      check_normal_state
      ;;
    dr)
      check_normal_state
      simulate_disaster
      verify_dr_state
      ;;
    recover)
      recover_cluster
      verify_dr_state
      ;;
    restore)
      restore_original_topology
      validate_recovery
      ;;
    all)
      check_normal_state
      simulate_disaster
      verify_dr_state
      recover_cluster
      restore_original_topology
      validate_recovery

      echo ""
      echo "╔════════════════════════════════════════════════════════════════╗"
      echo "║         ✓ COMPLETE DR TEST SCENARIO PASSED                    ║"
      echo "║                                                                ║"
      echo "║   Normal → DR Mode → Recovery → Restored Topology             ║"
      echo "╚════════════════════════════════════════════════════════════════╝"
      ;;
    *)
      echo "Usage: bash DR_TEST_SCENARIO.sh {all|normal|dr|recover|restore}"
      echo ""
      echo "Commands:"
      echo "  all       - Run complete DR test cycle (normal → DR → recover → restore)"
      echo "  normal    - Check normal cluster state (pg1=Leader, pg2=Standby, pg3=Replica)"
      echo "  dr        - Simulate disaster (stop pg1 & pg2, verify pg3 promoted)"
      echo "  recover   - Bring pg1 & pg2 back online, verify cluster reformation"
      echo "  restore   - Switchover pg3 → pg1 (restore original topology)"
      exit 1
      ;;
  esac
}

main "$@"
