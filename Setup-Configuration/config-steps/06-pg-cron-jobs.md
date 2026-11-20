## 6. Set up database maintenance jobs using pg_cron

Requires `pg_cron` in `shared_preload_libraries` and `cron.database_name` (see [Extensions, section 5.2](05-extensions.md)).

```sql
-- run in the database set by cron.database_name (default 'postgres')
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Example jobs (times are server time, cron syntax)
SELECT cron.schedule('nightly-analyze', '30 2 * * *', 'ANALYZE');
SELECT cron.schedule('weekly-vacuum-analyze', '0 3 * * 0', 'VACUUM (ANALYZE)');

-- review jobs and their run history
SELECT jobid, jobname, schedule, command, database, active FROM cron.job;
SELECT jobid, status, return_message, start_time, end_time FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;

-- remove a job
SELECT cron.unschedule('nightly-analyze');
```

Use `cron.schedule_in_database(job_name, schedule, command, database)` to run a job in a database other than `cron.database_name`.
