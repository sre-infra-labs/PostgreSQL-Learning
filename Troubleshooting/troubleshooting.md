# Troubleshooting

## Check Disk Usage
```
df -h
# exclude memory-based filesystems like tmpfs
df -lh --total -x tmpfs
# display in gigabytes
df -BG

### disk usage at directory/file level
sudo du -a /var/lib | sort -n -r | head -n 20

# interactive disk usage view
sudo ncdu /var

# check if deleted open files consuming space
sudo lsof | grep deleted

```

## Viewing Running Processes

```
# get currently running processes
ps -ef
ps aux

# get top 10 processes sorted by memory consumption
ps aux --sort=-%mem | head -n 10

# get top 10 processes sorted by cpu consumption
ps -eo pid,ppid,user,%cpu,%mem,cmd --sort=-%cpu
ps aux --sort=-%cpu | head -n 10

# find postgres related processes
ps -fp $(pgrep -d, -f postgres)

# interactively check processes
top
htop

```

## Checking System Uptime
```
uptime
uptime -p

uptime -p | awk '{print "Uptime:", $2, $3, $4, $5}'
ssh user@remote_host “uptime”

```

## Viewing System Logs

```
# display kernel messages and boot information
sudo dmesg

# get systemd logs which collects kernel, services, and application logs
journalctl
journalctl -u postgres
journalctl | grep postgres | head -n 20

# get logs from current boot
journalctl -b

# get newest entries first
journalctl -b -r

# filter logs for a time duration
journalctl --since “2025-02-20 08:00:00” --until “2025-02-20 10:00:00”
```

## Checking Memory Usage

```
# get memory usage
free -h
free -m

# inspect memory usage per process
ps -eo pid,user,%mem,%cpu,comm --sort=-%mem | head -n 10

# prints system uptime followed by memory statistics in a human-friendly format.
uptime; free -h

# monitor memory usage in real time
watch -n 1 free -h
```

## vim /tmp/ps_aggregate.sh; chmod +x /tmp/ps_aggregate.sh
```
#!/bin/bash

# Define a function to determine the sort keys based on the column name
get_sort_key() {
    local col_name="$1"
    case "$col_name" in
        TOTAL_%MEM) echo "-k2 -rn" ;;
        AVG_%MEM) echo "-k3 -rn" ;;
        TOTAL_%CPU) echo "-k4 -rn" ;;
        AVG_%CPU) echo "-k5 -rn" ;;
        INSTANCES) echo "-k6 -rn" ;;
        COMMAND) echo "-k1 -r" ;; # Sort by command name, reverse alphabetical
        *) echo "" ;; # Default to no sort if invalid name is provided
    esac
}

# --- Determine Sort Arguments ---

# Check if arguments were passed
if [ $# -eq 0 ]; then
    # Default sort if no arguments are provided
    SORT_COLS=('TOTAL_%CPU' 'TOTAL_%MEM')
else
    # Use provided arguments
    SORT_COLS=("$@")
fi

# Build the complete sort command arguments
SORT_ARGS=""
for col in "${SORT_COLS[@]}"; do
    key=$(get_sort_key "$col")
    if [ -n "$key" ]; then
        SORT_ARGS="$SORT_ARGS $key"
    fi
done

# --- Main Script Logic ---

ps -eo user,%mem,%cpu,comm --no-headers --sort=-%mem | \
awk '{
    # Aggregate CPU, MEM, and Count by Command (first part of the comm path)
    split($4, parts, "/")
    cmd = parts[1]
    mem[cmd] += $2
    cpu[cmd] += $3
    count[cmd]++
}
END {
    # Print data in pipe-separated format:
    # COMMAND|TOTAL_%MEM|AVG_%MEM|TOTAL_%CPU|AVG_%CPU|INSTANCES
    for (cmd in mem) {
        printf "%s|%.2f|%.2f|%.2f|%.2f|%d\n", 
               cmd, mem[cmd], mem[cmd]/count[cmd], cpu[cmd], cpu[cmd]/count[cmd], count[cmd]
    }
}' | sort -t'|' ${SORT_ARGS} | \
awk 'BEGIN {
    # Print headers
    printf "%-30s %12s %10s %12s %10s %10s\n", "COMMAND", "TOTAL_%MEM", "AVG_%MEM", "TOTAL_%CPU", "AVG_%CPU", "INSTANCES"
    printf "%-30s %12s %10s %12s %10s %10s\n", "-------", "----------", "--------", "----------", "--------", "---------"
    FS="|"
}
{
    # Print formatted output
    printf "%-30s %12.2f %10.2f %12.2f %10.2f %10d\n", $1, $2, $3, $4, $5, $6
}'
```

### Usage

```
/tmp/ps_aggregate.sh | head -n 11
watch -n 2 bash /tmp/ps_aggregate.sh
./ps_aggregate.sh	Sorts by default: TOTAL_%CPU (descending), then TOTAL_%MEM (descending).
./ps_aggregate.sh 'TOTAL_%MEM'	Sorts by TOTAL_%MEM (descending).
./ps_aggregate.sh 'INSTANCES' 'TOTAL_%CPU'	Sorts by INSTANCES (descending), then TOTAL_%CPU (descending).
./ps_aggregate.sh 'COMMAND' 'AVG_%MEM'	Sorts by COMMAND (reverse alphabetical), then AVG_%MEM (descending).
```


## Basic Networking in Linux

```


```




