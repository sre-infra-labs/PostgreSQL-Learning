#!/bin/bash

# Accept hosts file as first argument, default to hosts__multi_datacenter.yml
HOSTS_FILE="${1:-hosts__multi_datacenter.yml}"

while true; do
    echo -e "\e[1;33m===== $(date '+%Y-%m-%d %H:%M:%S') =====\e[0m"

    echo "--- DC1 Leader ---"
    ansible dc1_leader -i "$HOSTS_FILE" -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

    echo "--- DC2 Leader ---"
    ansible dc2_leader -i "$HOSTS_FILE" -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

    # Add 2 empty lines for readability
    echo
    echo

    # Wait 10 seconds before next iteration
    sleep 10
done


# pwd -> ~/GitHub/PostgreSQL-Learning/playbook-install-pg-cluster-redhat
# chmod +x check_patroni_loop.sh
# ./check_patroni_loop.sh
# ./check_patroni_loop.sh hosts__multi_datacenter.yml
