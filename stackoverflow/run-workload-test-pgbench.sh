#!/bin/bash

# PostgreSQL Workload Test using pgbench (Equivalent to SqlQueryStress)
# Test usp_randomq() dispatcher function with configurable threads and iterations
# Supports remote database connections with flexible authentication
#
# Usage:
#   ./run-workload-test-pgbench.sh                                    # Default: localhost, stackoverflow2013
#   ./run-workload-test-pgbench.sh --threads 4 --iterations 250
#   ./run-workload-test-pgbench.sh -d mydb -h 192.168.1.100 -U postgres
#   ./run-workload-test-pgbench.sh -d mydb -h remote.host.com -U user -W

# PostgreSQL Connection Parameters (Defaults)
DATABASE="stackoverflow2013"
HOST=""
PORT=""
USER=""
PASSWORD=""

# Workload Parameters
THREADS=8
ITERATIONS=500

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--database)
      DATABASE="$2"
      shift 2
      ;;
    -h|--host)
      HOST="$2"
      shift 2
      ;;
    -p|--port)
      PORT="$2"
      shift 2
      ;;
    -U|--username)
      USER="$2"
      shift 2
      ;;
    -W|--password)
      PASSWORD="$2"
      shift 2
      ;;
    --threads)
      THREADS="$2"
      shift 2
      ;;
    --iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [CONNECTION OPTIONS] [WORKLOAD OPTIONS]"
      echo ""
      echo "Connection Options (similar to pgbench):"
      echo "  -d, --database NAME    Database name (default: stackoverflow2013)"
      echo "  -h, --host HOST        Server host (default: localhost)"
      echo "  -p, --port PORT        Server port (default: 5432)"
      echo "  -U, --username USER    Database user (default: current user)"
      echo "  -W, --password PASS    Database password (default: use .pgpass or no password)"
      echo ""
      echo "Workload Options:"
      echo "  --threads NUM          Number of concurrent threads (default: 8)"
      echo "  --iterations NUM       Iterations per thread (default: 500)"
      echo ""
      echo "Examples:"
      echo "  $0"
      echo "    # Default: localhost, stackoverflow2013, 8×500"
      echo ""
      echo "  $0 --threads 4 --iterations 250"
      echo "    # Custom workload, localhost, stackoverflow2013"
      echo ""
      echo "  $0 -d mydb -h 192.168.1.100 -U postgres -W mypassword"
      echo "    # Remote host with authentication"
      echo ""
      echo "  $0 -d mydb -h remote.example.com -U appuser --threads 16"
      echo "    # Remote host with .pgpass authentication, heavy load"
      echo ""
      echo "Authentication Methods:"
      echo "  • Without -W: Uses .pgpass file if available, or connects without password"
      echo "  • With -W:    Provides password directly (for scripting)"
      echo ""
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

TOTAL_QUERIES=$((THREADS * ITERATIONS))

echo "=========================================="
echo "PostgreSQL Workload Testing - pgbench"
echo "=========================================="
echo "Connection Settings:"
echo "  Database: $DATABASE"
if [ -n "$HOST" ]; then
  echo "  Host: $HOST"
else
  echo "  Host: localhost (default)"
fi
if [ -n "$PORT" ]; then
  echo "  Port: $PORT"
else
  echo "  Port: 5432 (default)"
fi
if [ -n "$USER" ]; then
  echo "  User: $USER"
else
  echo "  User: current user (default)"
fi
if [ -n "$PASSWORD" ]; then
  echo "  Authentication: password provided"
else
  echo "  Authentication: .pgpass or no password"
fi
echo ""
echo "Workload Settings:"
echo "  Threads: $THREADS"
echo "  Iterations per thread: $ITERATIONS"
echo "  Total queries to execute: $TOTAL_QUERIES"
echo "  Function: usp_randomq()"
echo ""

# Create temporary test SQL file
TEST_SQL="/tmp/randomq-test.sql"
cat > $TEST_SQL << 'EOF'
SELECT * FROM usp_randomq() LIMIT 1;
EOF

echo "Test SQL:"
cat $TEST_SQL
echo ""
echo "=========================================="
echo "Starting workload test..."
echo "=========================================="
echo ""

# Build pgbench command with connection parameters
# -c: number of concurrent database clients
# -j: number of threads
# -t: number of transactions per client
# -f: SQL file to run
# -d: database name
# -h: host
# -p: port
# -U: username
# -W: password (environment variable PGPASSWORD)

PGBENCH_CMD="pgbench -d $DATABASE -c $THREADS -j $THREADS -t $ITERATIONS -f $TEST_SQL --no-vacuum --progress=100"

# Add optional connection parameters
if [ -n "$HOST" ]; then
  PGBENCH_CMD="$PGBENCH_CMD -h $HOST"
fi

if [ -n "$PORT" ]; then
  PGBENCH_CMD="$PGBENCH_CMD -p $PORT"
fi

if [ -n "$USER" ]; then
  PGBENCH_CMD="$PGBENCH_CMD -U $USER"
fi

# Handle password authentication
if [ -n "$PASSWORD" ]; then
  export PGPASSWORD="$PASSWORD"
fi

# Execute pgbench
eval "$PGBENCH_CMD"
PGBENCH_EXIT_CODE=$?

# Clear password from environment if it was set
if [ -n "$PASSWORD" ]; then
  unset PGPASSWORD
fi

echo ""
echo "=========================================="
if [ $PGBENCH_EXIT_CODE -eq 0 ]; then
  echo "✓ Workload test completed successfully!"
else
  echo "✗ Workload test failed with exit code: $PGBENCH_EXIT_CODE"
fi
echo "=========================================="

# Cleanup
rm -f $TEST_SQL

exit $PGBENCH_EXIT_CODE
