# Scan patroni logs for specific time range and keywords
# Scan postgresql logs for specific time range and keywords
awk '$0 >= "2025-03-27 07:00" && $0 <= "2025-03-27 07:40"' /var/log/patroni/patroni.log | less
awk '$0 >= "2025-03-27 07:00" && $0 <= "2025-03-27 07:40"' /var/log/postgresql/postgresql-Thu.log | less
grep -iE 'Deregister|Register|starting' /var/log/consul/consul.log | less

# Find total lines in file, and extract few lines from the middle
wc -l /var/log/postgresql/postgresql-Thu.log
awk 'NR>=500 && NR<=600' /var/log/postgresql/postgresql-Thu.log | less

# read active settings from postgresql.conf
  # read lines not starting with # or empty lines
grep -vE '^\s*#|^\s*$' /etc/postgresql/16/main/postgresql.conf