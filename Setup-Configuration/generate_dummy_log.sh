#!/bin/bash

# Target log file
LOG_FILE="/var/lib/postgresql/16/main/log/postgresql-Fri.log"

# Create log directory if not exists
mkdir -p "$(dirname "$LOG_FILE")"

# Dummy log line (about 100 bytes)
LOG_LINE="[$(date)] INFO Dummy log entry for testing log size growth. ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n"

# Approx 4.2 MB per second = ~42000 lines/sec (100 bytes * 42000 ≈ 4.2 MB)
LINES_PER_SEC=42000

echo "Writing logs to $LOG_FILE at ~250 MB/minute..."
while true; do
    for i in $(seq 1 $LINES_PER_SEC); do
        echo -ne "$LOG_LINE" >> "$LOG_FILE"
    done
    sleep 1
done

# chmod +x etc_logrotate.d_postgresql
# ./etc_logrotate.d_postgresql
# ls -lhS /var/lib/postgresql/16/main/log/