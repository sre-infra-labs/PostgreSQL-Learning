## 7. Enable vacuuming (autovacuum)

Autovacuum is on by default. Confirm it, then tune the important parameters:

```sql
SHOW autovacuum;

SELECT name, setting FROM pg_settings
WHERE name IN ('autovacuum','autovacuum_max_workers','autovacuum_naptime',
               'autovacuum_vacuum_scale_factor','autovacuum_analyze_scale_factor',
               'autovacuum_vacuum_cost_limit');
```

Starting point in `conf.d/dba.conf`:

```conf
autovacuum = on                          # run the autovacuum launcher and workers (default: on); keep on
autovacuum_max_workers = 4               # max autovacuum workers running at once (default: 3); requires restart
autovacuum_naptime = '30s'               # sleep between autovacuum checks per database (default: 1min); lower = checks more often
autovacuum_vacuum_scale_factor = 0.05    # fraction of rows that must be dead before VACUUM (default: 0.2)
autovacuum_analyze_scale_factor = 0.02   # fraction of rows that must change before ANALYZE (default: 0.1)
autovacuum_vacuum_cost_limit = 2000      # I/O cost budget per round before a worker sleeps (default: -1, i.e. vacuum_cost_limit = 200); higher = faster vacuum, more I/O
```

Find tables that need attention:

```sql
SELECT relname, n_dead_tup, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;
```
