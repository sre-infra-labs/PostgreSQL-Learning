## 8. Enable stats collection

Statistics collection is on by default (`track_counts`, `track_activities`, `track_io_timing` is off by default).

```conf
track_counts = on                # collect table/index access counters used by pg_stat_user_tables etc. (default: on; required for autovacuum)
track_activities = on            # record the current command of each session for pg_stat_activity (default: on)
track_activity_query_size = 4096 # max bytes of query text kept in pg_stat_activity per session (default: 1024); longer queries are cut off
track_io_timing = on             # time block reads/writes; small overhead; feeds EXPLAIN (BUFFERS) and pg_stat_statements I/O columns (default: off)
```

Verify:

```sql
SHOW track_counts;
SHOW track_io_timing;
```

Reset counters when needed:

```sql
SELECT pg_stat_reset();                      -- database-level counters
SELECT pg_stat_statements_reset();           -- after pg_stat_statements is installed
```
