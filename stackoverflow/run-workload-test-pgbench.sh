#!/bin/bash

# PostgreSQL Workload Test using pgbench (Equivalent to SqlQueryStress)
# Test usp_randomq() dispatcher function with configurable threads and iterations
#
# Usage:
#   ./run-workload-test-pgbench.sh                    # Default: 8 threads, 500 iterations
#   ./run-workload-test-pgbench.sh --threads 4 --iterations 250
#   ./run-workload-test-pgbench.sh --threads 16

DATABASE="stackoverflow2013"
THREADS=8
ITERATIONS=500

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --threads)
      THREADS="$2"
      shift 2
      ;;
    --iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --threads NUM       Number of concurrent threads (default: 8)"
      echo "  --iterations NUM    Iterations per thread (default: 500)"
      echo "  -h, --help          Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                              # 8 threads × 500 iterations"
      echo "  $0 --threads 4 --iterations 250 # 4 threads × 250 iterations"
      echo "  $0 --threads 16                 # 16 threads × 500 iterations"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

TOTAL_QUERIES=$((THREADS * ITERATIONS))

echo "=========================================="
echo "PostgreSQL Workload Testing - pgbench"
echo "=========================================="
echo "Database: $DATABASE"
echo "Threads: $THREADS"
echo "Iterations per thread: $ITERATIONS"
echo "Total queries to execute: $TOTAL_QUERIES"
echo "Function: usp_randomq()"
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

# Run pgbench
# -c: number of concurrent database clients
# -j: number of threads
# -t: number of transactions per client
# -f: SQL file to run
pgbench -d $DATABASE \
  -c $THREADS \
  -j $THREADS \
  -t $ITERATIONS \
  -f $TEST_SQL \
  --no-vacuum \
  --progress=100

echo ""
echo "=========================================="
echo "Workload test completed!"
echo "=========================================="

# Cleanup
rm -f $TEST_SQL
