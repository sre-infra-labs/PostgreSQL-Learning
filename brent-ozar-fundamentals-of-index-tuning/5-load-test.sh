#!/usr/bin/env bash

# Usage: ./run_workload.sh [progress_sec] [clients] [duration_sec]
# Example: ./run_workload.sh 10 8 120

#ls ./5-workload/*.sql | xargs -I{} echo --file={} | xargs pgbench -P 30 -c 6 -j 6 -T 300 stackoverflow

PROGRESS="${1:-30}"
CLIENTS="${2:-6}"
DURATION="${3:-300}"
DB_NAME="stackoverflow"

# Collect all SQL workload files safely into an array
files=()
for f in ./5-workload/*.sql; do
    files+=("--file=$f")
done

echo "Starting pgbench on '$DB_NAME' | Clients: $CLIENTS | Duration: ${DURATION}s | Progress every: ${PROGRESS}s"

pgbench -n -P "$PROGRESS" -c "$CLIENTS" -j "$CLIENTS" -T "$DURATION" "${files[@]}" "$DB_NAME"


