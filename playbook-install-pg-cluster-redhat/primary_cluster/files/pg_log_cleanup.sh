#!/bin/bash
#
# PostgreSQL Log Cleanup Script
# Run as postgres user via cron
# Usage: ./pg_log_cleanup.sh [threshold_in_gb] [slack_webhook_url]
#

# Don't exit on errors - we'll handle them individually
set -uo pipefail

# Configuration
LOG_DIRECTORY_SIZE_THRESHOLD_GB=${1:-5}
THRESHOLD_BYTES=$((LOG_DIRECTORY_SIZE_THRESHOLD_GB * 1024 * 1024 * 1024))
SLACK_WEBHOOK_URL=${2:-"https://hooks.slack.com/services/YOUR/WEBHOOK/URL"}

# Get hostname
HOSTNAME=$(hostname)

# Track if there were any failures
SCRIPT_FAILED=0
FAILURE_MESSAGES=()

# Temporary variables for log directory (will be set after querying PostgreSQL)
FULL_LOG_DIR=""
SCRIPT_LOG_FILE=""

# Function to log messages (to both stdout and log file if available)
log_message() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$msg"
    if [[ -n "$SCRIPT_LOG_FILE" ]] && [[ -w "$SCRIPT_LOG_FILE" ]]; then
        echo "$msg" >> "$SCRIPT_LOG_FILE" 2>/dev/null || true
    fi
}

# Function to send Slack notification
send_slack_notification() {
    local message="$1"
    local color="${2:-danger}"

    if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
        log_message "Warning: Slack webhook URL not configured, skipping notification"
        return
    fi

    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "PostgreSQL Log Cleanup Failure",
            "fields": [
                {
                    "title": "Hostname",
                    "value": "$HOSTNAME",
                    "short": true
                },
                {
                    "title": "Log Directory",
                    "value": "$FULL_LOG_DIR",
                    "short": true
                },
                {
                    "title": "Threshold",
                    "value": "${LOG_DIRECTORY_SIZE_THRESHOLD_GB}GB",
                    "short": true
                },
                {
                    "title": "Current Size",
                    "value": "${CURRENT_SIZE_GB}GB",
                    "short": true
                },
                {
                    "title": "Details",
                    "value": "$message",
                    "short": false
                }
            ],
            "footer": "PostgreSQL Log Cleanup Script",
            "ts": $(date +%s)
        }
    ]
}
EOF
)

    curl -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK_URL" 2>/dev/null || {
        log_message "Error: Failed to send Slack notification"
    }
}

# Function to cleanup old script log files (older than 24 hours)
cleanup_old_script_logs() {
    if [[ -z "$FULL_LOG_DIR" ]] || [[ ! -d "$FULL_LOG_DIR" ]]; then
        return
    fi

    log_message "Cleaning up old script log files (older than 24 hours)..."

    local old_logs_count=0
    local old_logs_size=0

    # Find and delete script log files older than 24 hours
    while IFS= read -r -d '' old_log; do
        local file_size=$(stat -c%s "$old_log" 2>/dev/null || echo 0)
        if rm -f "$old_log" 2>/dev/null; then
            log_message "Deleted old script log: $(basename "$old_log")"
            old_logs_count=$((old_logs_count + 1))
            old_logs_size=$((old_logs_size + file_size))
        else
            log_message "Warning: Failed to delete old script log: $(basename "$old_log")"
        fi
    done < <(find "$FULL_LOG_DIR" -type f -name "pg_log_cleanup--*.log" -mtime +1 -print0 2>/dev/null)
    
    if [[ $old_logs_count -gt 0 ]]; then
        local freed_mb=$(echo "scale=2; $old_logs_size / 1024 / 1024" | bc 2>/dev/null || echo "0")
        log_message "Cleaned up $old_logs_count old script log files, freed ${freed_mb}MB"
    else
        log_message "No old script log files to clean up"
    fi
}

# Get log directory from PostgreSQL
LOG_DIR=$(psql -t -c "SHOW log_directory;" 2>/dev/null | xargs) || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Unable to connect to PostgreSQL or query log_directory"
    FAILURE_MESSAGES+=("Unable to connect to PostgreSQL or query log_directory")
    SCRIPT_FAILED=1
    CURRENT_SIZE_GB="N/A"
    FULL_LOG_DIR="Unknown"
    send_slack_notification "Failed to connect to PostgreSQL database on $HOSTNAME"
    exit 1
}

DATA_DIR=$(psql -t -c "SHOW data_directory;" 2>/dev/null | xargs) || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Unable to query data_directory"
    FAILURE_MESSAGES+=("Unable to query data_directory from PostgreSQL")
    SCRIPT_FAILED=1
    CURRENT_SIZE_GB="N/A"
    FULL_LOG_DIR="Unknown"
    send_slack_notification "Failed to query data_directory from PostgreSQL on $HOSTNAME"
    exit 1
}

# Construct full path to log directory
if [[ "$LOG_DIR" = /* ]]; then
    # Absolute path
    FULL_LOG_DIR="$LOG_DIR"
else
    # Relative path to data directory
    FULL_LOG_DIR="${DATA_DIR}/${LOG_DIR}"
fi

# Check if log directory exists
if [[ ! -d "$FULL_LOG_DIR" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Log directory $FULL_LOG_DIR does not exist"
    FAILURE_MESSAGES+=("Log directory $FULL_LOG_DIR does not exist")
    SCRIPT_FAILED=1
    CURRENT_SIZE_GB="N/A"
    send_slack_notification "Log directory $FULL_LOG_DIR does not exist on $HOSTNAME"
    exit 1
fi

# Create script log file in PostgreSQL log directory
SCRIPT_LOG_FILE="${FULL_LOG_DIR}/pg_log_cleanup--$(date '+%Y-%m-%d_%H%M%S').log"

# Try to create the log file
touch "$SCRIPT_LOG_FILE" 2>/dev/null || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Warning: Cannot create log file $SCRIPT_LOG_FILE, continuing without file logging"
    SCRIPT_LOG_FILE=""
}

# Now that we have the log file, log the start
log_message "=== PostgreSQL Log Cleanup Script Started ==="
log_message "Hostname: $HOSTNAME"
log_message "Threshold: ${LOG_DIRECTORY_SIZE_THRESHOLD_GB}GB"

# Clean up old script log files first (older than 24 hours)
cleanup_old_script_logs

# Function to get directory size in bytes (with error handling)
get_dir_size() {
    local size
    size=$(du -sb "$1" 2>/dev/null | awk '{print $1}')
    if [[ -z "$size" ]]; then
        echo "0"
    else
        echo "$size"
    fi
}

# Get current directory size
CURRENT_SIZE=$(get_dir_size "$FULL_LOG_DIR")
CURRENT_SIZE_GB=$(echo "scale=2; $CURRENT_SIZE / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0")

log_message "Log directory: $FULL_LOG_DIR"
log_message "Current size: ${CURRENT_SIZE_GB}GB (threshold: ${LOG_DIRECTORY_SIZE_THRESHOLD_GB}GB)"

# Check if cleanup is needed
if [[ $CURRENT_SIZE -le $THRESHOLD_BYTES ]]; then
    log_message "Log directory size is under threshold. No cleanup needed."
    log_message "=== Script Completed Successfully ==="
    
    # Remove current script log file since there were no issues
    if [[ -n "$SCRIPT_LOG_FILE" ]] && [[ -f "$SCRIPT_LOG_FILE" ]]; then
        rm -f "$SCRIPT_LOG_FILE" 2>/dev/null || true
    fi
    
    exit 0
fi

log_message "Log directory size exceeds threshold. Starting cleanup..."

# Get current log file (most recently modified) - handle errors
CURRENT_LOG=$(ls -t "$FULL_LOG_DIR"/postgresql-*.log* 2>/dev/null | head -n1) || CURRENT_LOG=""

# Create temporary file list
TEMP_FILE_LIST=$(mktemp)
trap "rm -f $TEMP_FILE_LIST" EXIT

# Find log files and sort by age (oldest first) - ignore errors
# Exclude pg_log_cleanup log files from deletion
find "$FULL_LOG_DIR" -type f -name "postgresql-*.log*" -printf "%T@ %p\n" 2>/dev/null | \
    sort -n 2>/dev/null | \
    awk '{print $2}' | \
    grep -v "pg_log_cleanup--" > "$TEMP_FILE_LIST" || {
    log_message "Warning: Error finding log files, continuing with available files"
    FAILURE_MESSAGES+=("Error finding log files in $FULL_LOG_DIR")
}

# Remove current log from list if it exists
if [[ -n "$CURRENT_LOG" ]]; then
    grep -v "^${CURRENT_LOG}$" "$TEMP_FILE_LIST" > "${TEMP_FILE_LIST}.tmp" 2>/dev/null || true
    mv "${TEMP_FILE_LIST}.tmp" "$TEMP_FILE_LIST" 2>/dev/null || true
fi

# Also remove the current script log file from deletion list
if [[ -n "$SCRIPT_LOG_FILE" ]]; then
    grep -v "^${SCRIPT_LOG_FILE}$" "$TEMP_FILE_LIST" > "${TEMP_FILE_LIST}.tmp" 2>/dev/null || true
    mv "${TEMP_FILE_LIST}.tmp" "$TEMP_FILE_LIST" 2>/dev/null || true
fi

# Delete files until size is under threshold
DELETED_COUNT=0
DELETED_SIZE=0
SKIPPED_COUNT=0

log_message "Starting file deletion process..."

while [[ $CURRENT_SIZE -gt $THRESHOLD_BYTES ]] && [[ -s "$TEMP_FILE_LIST" ]]; do
    # Get oldest file
    OLDEST_FILE=$(head -n1 "$TEMP_FILE_LIST" 2>/dev/null)
    
    if [[ -z "$OLDEST_FILE" ]]; then
        break
    fi
    
    # Check if file still exists and is readable
    if [[ ! -f "$OLDEST_FILE" ]]; then
        log_message "Warning: File no longer exists: $(basename "$OLDEST_FILE")"
        FAILURE_MESSAGES+=("File no longer exists: $(basename "$OLDEST_FILE")")
        sed -i '1d' "$TEMP_FILE_LIST" 2>/dev/null || true
        continue
    fi
    
    if [[ ! -r "$OLDEST_FILE" ]]; then
        log_message "Warning: Permission denied, skipping: $(basename "$OLDEST_FILE")"
        FAILURE_MESSAGES+=("Permission denied: $(basename "$OLDEST_FILE")")
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        sed -i '1d' "$TEMP_FILE_LIST" 2>/dev/null || true
        continue
    fi
    
    # Get file size - handle errors
    FILE_SIZE=$(stat -c%s "$OLDEST_FILE" 2>/dev/null)
    if [[ -z "$FILE_SIZE" ]] || [[ "$FILE_SIZE" -eq 0 ]]; then
        log_message "Warning: Unable to get size for $(basename "$OLDEST_FILE"), assuming 0 bytes"
        FAILURE_MESSAGES+=("Unable to get size: $(basename "$OLDEST_FILE")")
        FILE_SIZE=0
    fi
    
    # Try to delete the file
    if rm -f "$OLDEST_FILE" 2>/dev/null; then
        FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1024 / 1024" | bc 2>/dev/null || echo "0")
        log_message "Deleted: $(basename "$OLDEST_FILE") (${FILE_SIZE_MB}MB)"
        DELETED_COUNT=$((DELETED_COUNT + 1))
        DELETED_SIZE=$((DELETED_SIZE + FILE_SIZE))
        CURRENT_SIZE=$((CURRENT_SIZE - FILE_SIZE))
    else
        log_message "Warning: Failed to delete $(basename "$OLDEST_FILE") (permission denied or file in use), skipping"
        FAILURE_MESSAGES+=("Failed to delete: $(basename "$OLDEST_FILE")")
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
    
    # Remove from list - ignore errors
    sed -i '1d' "$TEMP_FILE_LIST" 2>/dev/null || true
done

# Final summary
FINAL_SIZE_GB=$(echo "scale=2; $CURRENT_SIZE / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0")
DELETED_SIZE_GB=$(echo "scale=2; $DELETED_SIZE / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0")

log_message "=== Cleanup Complete ==="
log_message "  Files deleted: $DELETED_COUNT"
log_message "  Files skipped (permission/access issues): $SKIPPED_COUNT"
log_message "  Space freed: ${DELETED_SIZE_GB}GB"
log_message "  Final size: ${FINAL_SIZE_GB}GB"

# Check if cleanup was successful
if [[ $CURRENT_SIZE -gt $THRESHOLD_BYTES ]]; then
    log_message "WARNING: Log directory is still above threshold after cleanup."
    SCRIPT_FAILED=1
    FAILURE_MESSAGES+=("Log directory still above threshold: ${FINAL_SIZE_GB}GB > ${LOG_DIRECTORY_SIZE_THRESHOLD_GB}GB")
fi

# Check if there were significant issues during cleanup
if [[ $SKIPPED_COUNT -gt 0 ]] || [[ ${#FAILURE_MESSAGES[@]} -gt 0 ]]; then
    SCRIPT_FAILED=1
fi

# Send Slack notification if there were failures
if [[ $SCRIPT_FAILED -eq 1 ]]; then
    # Build failure message
    FAILURE_MSG="Cleanup issues detected:\n"
    FAILURE_MSG+="• Files deleted: $DELETED_COUNT\n"
    FAILURE_MSG+="• Files skipped: $SKIPPED_COUNT\n"
    FAILURE_MSG+="• Space freed: ${DELETED_SIZE_GB}GB\n"
    FAILURE_MSG+="• Final size: ${FINAL_SIZE_GB}GB (Threshold: ${LOG_DIRECTORY_SIZE_THRESHOLD_GB}GB)\n\n"
    
    if [[ ${#FAILURE_MESSAGES[@]} -gt 0 ]]; then
        FAILURE_MSG+="Issues encountered:\n"
        for msg in "${FAILURE_MESSAGES[@]}"; do
            FAILURE_MSG+="• $msg\n"
        done
    fi
    
    send_slack_notification "$FAILURE_MSG"
    log_message "Slack notification sent about cleanup issues"
    log_message "Script log preserved at: $SCRIPT_LOG_FILE"
else
    log_message "No errors detected. Removing current script log file."
    # Remove current script log file since there were no issues
    if [[ -n "$SCRIPT_LOG_FILE" ]] && [[ -f "$SCRIPT_LOG_FILE" ]]; then
        rm -f "$SCRIPT_LOG_FILE" 2>/dev/null || {
            log_message "Warning: Failed to remove current script log file"
        }
    fi
fi

log_message "=== Script Completed ==="

exit 0

# sudo -u postgres /var/lib/pgsql/pg_log_cleanup.sh 5 "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# 0/5 * * * * sudo -u postgres /var/lib/pgsql/pg_log_cleanup.sh 5 "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" >> /var/lib/pgsql/log_cleanup.log 2>&1


