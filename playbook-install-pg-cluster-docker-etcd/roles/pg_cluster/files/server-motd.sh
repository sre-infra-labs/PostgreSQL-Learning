#!/bin/bash

# ============================================================
# Custom Server MOTD
# ============================================================

# Colors
BOLD=$'\033[1m'
RESET=$'\033[0m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'
WHITE=$'\033[37m'
BLACK_BG=$'\033[40m'
GRAY=$'\033[90m'

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

section()
{
    local title="$1" width left right
    width=$(tput cols 2>/dev/null || echo 120)
    [ "$width" -gt 85 ] && width=85
    [ "$width" -lt 40 ] && width=40
    left=$(( (width - ${#title}) / 2 ))
    right=$(( width - ${#title} - left ))

    printf '%*s' "$left" '' | tr ' ' '='
    printf '%s%s%s%s' "$BLACK_BG" "$WHITE" "$title" "$RESET"
    printf '%*s\n' "$right" '' | tr ' ' '='
}

item()
{
    local label="$1"
    local value="$2"

    printf " - %-20s : %s\n" "$label" "$value"
}

# ------------------------------------------------------------
# User Data
# ------------------------------------------------------------

section " User Data "

HOSTNAME=$(hostname -f 2>/dev/null || hostname)

if [ -f /etc/redhat-release ]; then
    RELEASE=$(cat /etc/redhat-release)
else
    RELEASE=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2- | tr -d '"')
fi

USER_COUNT=$(who | wc -l)

item "Hostname" "$HOSTNAME"
item "Release" "$RELEASE"
item "Users" "Currently ${USER_COUNT} user(s) logged on"

# ------------------------------------------------------------
# Hardware Data
# ------------------------------------------------------------

section " Hardware Data "

MANUFACTURER=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || echo "Unknown")
MACHINE_TYPE=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "Unknown")
MACHINE_MODEL=$(cat /sys/devices/virtual/dmi/id/product_version 2>/dev/null || echo "Unknown")

item "Manufacturer" "$MANUFACTURER"
item "Machine Type" "$MACHINE_TYPE"
item "Machine Model" "$MACHINE_MODEL"
item "Serial Number" "Only accessible by root"

# ------------------------------------------------------------
# System Data
# ------------------------------------------------------------

section " System Data "

# CPU load
LOAD=$(awk '{print $1", "$2", "$3}' /proc/loadavg)

# Memory
MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/^Mem:/ {print $3}')

# Swap
SWAP_USED=$(free -m | awk '/^Swap:/ {print $3}')

# Uptime
UPTIME=$(uptime -p | sed 's/^up //')

# Disk
ROOT_FREE=$(df -h / | awk 'NR==2 {print $4}')
HOME_FREE=$(df -h /home 2>/dev/null | awk 'NR==2 {print $4}')

[ -z "$HOME_FREE" ] && HOME_FREE="N/A"

item "CPU usage" "$LOAD (1, 5, 15 min)"
item "Memory used" "${MEM_USED} MB / ${MEM_TOTAL} MB"
item "Swap in use" "${SWAP_USED} MB"
item "System uptime" "$UPTIME"
item "Disk space Root" "${ROOT_FREE} remaining"
item "Disk space Home" "${HOME_FREE} remaining"

echo