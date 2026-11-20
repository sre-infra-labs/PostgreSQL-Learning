## 16. Final verification checklist

```sql
SELECT version();
SHOW listen_addresses;
SHOW port;
SHOW shared_buffers;
SHOW work_mem;
SHOW maintenance_work_mem;
SHOW shared_preload_libraries;
SHOW logging_collector;
SHOW log_directory;
SHOW archive_mode;
SHOW autovacuum;
SHOW track_counts;
SELECT name FROM pg_available_extensions WHERE installed_version IS NOT NULL;
```

From a remote machine:

```bash
psql -h <server-ip> -U postgres -d postgres -c 'SELECT 1;'
```

Outstanding (to be documented): pg_exporter + Prometheus, pgwatch.
