#!/usr/bin/env bash

# Usage: ./run_workload.sh [duration_sec] [clients] [progress_sec]
# Example: ./run_workload.sh 300 6 30

#ls ./5-workload/*.sql | xargs -I{} echo --file={} | xargs pgbench -P 30 -c 6 -j 6 -T 300 stackoverflow

DURATION="${1:-300}"
CLIENTS="${2:-6}"
PROGRESS="${3:-30}"

DB_NAME="stackoverflow"

# Collect all SQL workload files safely into an array
files=()
for f in ./5-workload/*.sql; do
    files+=("--file=$f")
done

echo "Starting pgbench on '$DB_NAME' | Clients: $CLIENTS | Duration: ${DURATION}s | Progress every: ${PROGRESS}s"

pgbench -n -P "$PROGRESS" -c "$CLIENTS" -j "$CLIENTS" -T "$DURATION" "${files[@]}" "$DB_NAME"


