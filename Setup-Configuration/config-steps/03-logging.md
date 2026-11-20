## 3. Logging

Logs go to `/var/log/postgresql/`, rotated by size (100 MB) and age (every 1 day). Old files are compressed and removed by the cleanup job below.

```bash
sudo mkdir -p /var/log/postgresql
sudo chown postgres:postgres /var/log/postgresql
sudo chmod 0750 /var/log/postgresql
```

`conf.d/dba.conf`:

```conf
logging_collector = on
log_destination = 'stderr'
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_file_mode = '0640'
log_rotation_age = 1d
log_rotation_size = 50MB
log_truncate_on_rotation = on

log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_min_messages = 'warning'
log_min_error_statement = 'error'
log_lock_waits = on
deadlock_timeout = '5s'
log_temp_files = '20MB'
log_checkpoints = on
log_connections = on
log_disconnections = on

log_min_duration_statement = 500   # log statements slower than 500 ms
log_min_duration_sample = 100
log_statement_sample_rate = 0.8
log_transaction_sample_rate = 0.5


```

For pgBadger-compatible logs (optional, see `pgBadger-settings.md`), add the sampling settings. Lower `log_min_duration_statement` above if pgBadger needs more detail:

```conf
log_statement_sample_rate = 0.8
log_transaction_sample_rate = 0.5
```

Apply:

```bash
sudo systemctl restart postgresql
```

Verify:

```sql
SHOW logging_collector;
SHOW log_directory;
SHOW log_filename;
SHOW log_rotation_age;
SHOW log_rotation_size;
```

Expected output with the values above:

```text
 logging_collector
-------------------
 on

 log_directory
----------------------
 /var/log/postgresql

 log_filename
--------------------------------------
 postgresql-%Y-%m-%d_%H%M%S.log

 log_rotation_age
------------------
 1d

 log_rotation_size
-------------------
 100MB
```

Each `SHOW` returns one row. The `log_filename` pattern is expanded with the time the file was opened, so you should see files named like `postgresql-2026-11-20_082059.log` in `/var/log/postgresql/`.

### Clean up old log files

PostgreSQL does not delete old logs, and timestamped names create a new file at every rotation. Use a cron job that compresses logs after 7 days and deletes them after 30:

```bash
sudo tee /etc/cron.d/postgresql-log-cleanup > /dev/null <<'EOF'
SHELL=/bin/bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin
# compress logs older than 7 days
30 * * * * postgres find /var/log/postgresql -name 'postgresql-*.log' -mtime +7 -exec gzip {} \;
# delete compressed logs older than 30 days
40 * * * * postgres find /var/log/postgresql -name 'postgresql-*.log.gz' -mtime +30 -delete
EOF
sudo chown root:root /etc/cron.d/postgresql-log-cleanup
sudo chmod 0644 /etc/cron.d/postgresql-log-cleanup
```

Adjust `+7` and `+30` to your retention needs. The active log is never compressed or deleted, because it was modified recently.

Test the commands without deleting anything:

```bash
sudo -u postgres find /var/log/postgresql -name 'postgresql-*.log' -mtime +7 -print
sudo -u postgres find /var/log/postgresql -name 'postgresql-*.log.gz' -mtime +30 -print
```

Check disk usage:

```bash
du -sh /var/log/postgresql
```
