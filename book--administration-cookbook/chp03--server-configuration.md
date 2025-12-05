# Server Configuration

### `shared_buffers`
Increasing shared_buffers size would improve performance when db size is larger than 128 MB.

  - Should be set large enough to help in performance, but not too much so that `page file` & `Linux OOM` is avoided.

### `OOM`
Linux `Out Of Memory` killer terminates any process to relieve memory pressure on host.

### `wal_buffers`


### `min_wal_size`


### `max_max_size`


### `checkpoint_timeout`

### `checkpoint_completion_target`

### `work_mem`

### `maintenance_work_mem`

## Settings for heavy write activity and/or large data loads?


# Extensions available in Contrib

- `pg_stat_statements` - track statistics of SQL planning and execution
- `pg_audit`
- `auto_explain` - log execution plans of slow queries
- `dblink` - connect to other PostgreSQL databases
- `postgres_fdw` - access data stored in external PostgreSQL servers
- `file_fdw` - access data files in the server's file system
- `passwordcheck` - verify password strength
- `pg_buffercache` - inspect PostgreSQL buffer cache state
- `pg_overexplain` - allow EXPLAIN to dump even more details

# Extension available in pgxn

- `pg_stat_monitor` - aggregated information on top of pg_stat_statements
- `pg_top` - top like tool for postgresql processes
- `pg_systat` - is a systat for postgresql.
- `pg_stat_kcache` - An extension gathering CPU and disk acess statistics