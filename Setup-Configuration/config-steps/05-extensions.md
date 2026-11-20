## 5. Extensions

### 5.1 Install the packages (Ubuntu/Debian, PGDG repo)

Add the PostgreSQL apt repo first (see https://www.postgresql.org/download/linux/ubuntu/), then:

```bash
sudo apt update
sudo apt install -y postgresql-<ver>-pgaudit
sudo apt install -y postgresql-<ver>-cron            # pg_cron
sudo apt install -y postgresql-<ver>-repack          # pg_repack
sudo apt install -y postgresql-<ver>-partman         # pg_partman
sudo apt install -y postgresql-<ver>-pglogical
sudo apt install -y postgresql-<ver>-wal2json
sudo apt install -y postgresql-<ver>-pg-hint-plan
sudo apt install -y postgresql-<ver>-pg-wait-sampling
sudo apt install -y postgresql-contrib               # pg_stat_statements, auto_explain, pg_trgm, pg_buffercache, postgres_fdw ...
```

Not sure of a package name? Search for it:

```bash
apt search postgresql-<ver> | grep -i <extension-name>
```

Extensions that are not packaged (for example `pg_stat_plans`, `pg_plan_advice` on pg19+) must be built from source with `make USE_PGXS=1 install PG_CONFIG=/usr/lib/postgresql/<ver>/bin/pg_config`. Example from `book--learn-postgres/chp19-useful-tools-n-extensions.md` (pg_stat_monitor).

### 5.2 Extensions that must be preloaded (`shared_preload_libraries`)

Extensions in this list need a server restart after being added. Set them in one place (`conf.d/dba.conf`), not in several:

```conf
shared_preload_libraries = 'pg_stat_statements,auto_explain,pgaudit,pg_cron,pg_wait_sampling'

# pg_cron needs a database to hold its job table
cron.database_name = 'postgres'
```

Or use `ALTER SYSTEM` (writes to `postgresql.auto.conf`):

```sql
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements,auto_explain,pgaudit,pg_cron';
```

Then restart:

```bash
sudo systemctl restart postgresql
```

Confirm:

```sql
SHOW shared_preload_libraries;
```

Note: when you set `shared_preload_libraries` with `ALTER SYSTEM`, it replaces the whole list. Include every library you need.

### 5.3 auto_explain (log plans of slow queries)

```conf
session_preload_libraries = 'auto_explain'     # no restart needed; reload

auto_explain.log_min_duration = '1000ms'
auto_explain.log_analyze = on              # ANALYZE
auto_explain.log_settings = on             # SETTINGS (PG 12+)
auto_explain.log_timing = on               # TIMING (needs log_analyze)
auto_explain.log_buffers = on              # BUFFERS
auto_explain.log_wal = on                  # WAL (PG 13+, needs log_analyze)
auto_explain.log_verbose = on              # VERBOSE
auto_explain.log_format = 'json'           # FORMAT JSON
auto_explain.log_nested_statements = on
```

Mapping of the EXPLAIN options to auto_explain settings:
- `COSTS` and `SUMMARY`: there is no `auto_explain.log_costs` or `auto_explain.log_summary` setting. Costs are always included in logged plans, and the summary timing is included with `log_analyze`. Confirm after loading the library:

```sql
SELECT name, setting FROM pg_settings WHERE name LIKE 'auto_explain.%' ORDER BY name;
```

Per-database override:

```sql
ALTER DATABASE postgres_air SET auto_explain.log_min_duration = '1000ms';
```

### 5.4 pg_stat_statements (find the most expensive queries)

Requires `shared_preload_libraries` (see 5.2). Statistics are collected for the whole server, across all databases, once the library is preloaded. The extension only creates the `pg_stat_statements` view in the database where you run `CREATE EXTENSION`, so you need it in one database (such as `postgres`) to query the statistics. Creating it in more databases is not required.

```sql
-- run in the database you will query from (e.g. postgres)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Check that the statistics are visible from that database:

```sql
SELECT count(*) FROM pg_stat_statements;
```

Reference: `book--learn-postgres/chp19-useful-tools-n-extensions.md`

### 5.5 pgaudit (audit logging)

Requires `shared_preload_libraries = '...pgaudit...'`, then:

```sql
CREATE EXTENSION IF NOT EXISTS pgaudit;

-- Audit writes and DDL
ALTER SYSTEM SET pgaudit.log = 'write, ddl';
SELECT pg_reload_conf();
```

Other values for `pgaudit.log`: `ALL, NONE, READ, WRITE, ROLE, DDL, FUNCTION, MISC, MISC_SET`. Role-based auditing: create a role, grant it the tables to audit, then `ALTER SYSTEM SET pgaudit.role = 'pgaudit_role';`. Reference: `book--learn-postgres/chp14-logging-and-auditing.md`

### 5.6 pg_stat_plans (per-plan statistics, like pg_stat_statements but per plan)

Tracks call counts, execution times and EXPLAIN text for each plan of a query. Not packaged in the PGDG apt repo for every version, so build it from source (repo: https://github.com/pganalyze/pg_stat_plans). Requires PostgreSQL 16 or newer.

Build prerequisites (the server headers provide `postgres.h`; without them the build fails with `postgres.h: No such file or directory`):

```bash
sudo apt install -y postgresql-server-dev-18 libzstd-dev libssl-dev
```

```bash
git clone https://github.com/pganalyze/pg_stat_plans.git
cd pg_stat_plans
make USE_PGXS=1 PG_CONFIG=/usr/lib/postgresql/<ver>/bin/pg_config
sudo make USE_PGXS=1 PG_CONFIG=/usr/lib/postgresql/<ver>/bin/pg_config install
```

Preload it (needs a restart), in `conf.d/dba.conf`:

```conf
shared_preload_libraries = 'pg_stat_statements,auto_explain,pgaudit,pg_cron,pg_wait_sampling,pg_stat_plans'
# optional: compress stored plan texts
pg_stat_plans.compress = 'zstd'
```

Then restart and create the extension in each database you want to track:

```bash
sudo systemctl restart postgresql
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_plans;
```

Reference: https://github.com/pganalyze/pg_stat_plans

### 5.7 pg_query_state (inspect the state of a running query)

Lets you see the current execution state of a query in another backend, including its plan and per-node progress, while it is running. Source: https://github.com/postgrespro/pg_query_state. Not in the apt repo, so build from source.

**Warning:** this extension does not compile against the stock PostgreSQL packages. It needs two patches to the PostgreSQL core source, then a rebuild and reinstall of PostgreSQL itself. For PostgreSQL 18 the patches are `patches/custom_signals_18.0.patch` and `patches/runtime_explain_18.0.patch`. Building against the unpatched PGDG headers fails with `INVALID_PROCSIGNAL` and `RegisterCustomProcSignalHandler` undeclared errors. Decide whether you want a patched PostgreSQL build before following the steps below.

```bash
git clone https://github.com/postgrespro/pg_query_state.git
cd pg_query_state
make USE_PGXS=1 PG_CONFIG=/usr/lib/postgresql/<ver>/bin/pg_config
sudo make USE_PGXS=1 PG_CONFIG=/usr/lib/postgresql/<ver>/bin/pg_config install
```

Preload it (needs a restart), in `conf.d/dba.conf`:

```conf
shared_preload_libraries = 'pg_stat_statements,auto_explain,pgaudit,pg_cron,pg_wait_sampling,pg_query_state'
# optional: collect per-node timing (adds overhead; default off)
pg_query_state.enable_timing = off
```

Then restart and create the extension:

```bash
sudo systemctl restart postgresql
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_query_state;
```

Reference: https://github.com/postgrespro/pg_query_state

Note: as with the list in 5.2, `ALTER SYSTEM SET shared_preload_libraries` replaces the whole list. Include `pg_stat_plans` and `pg_query_state` alongside the others.

### 5.8 Other extensions (create in the database where needed)

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;          -- trigram indexes for LIKE / ILIKE / fuzzy search
CREATE EXTENSION IF NOT EXISTS pg_buffercache;   -- inspect shared_buffers contents
CREATE EXTENSION IF NOT EXISTS postgres_fdw;     -- query other PostgreSQL servers
CREATE EXTENSION IF NOT EXISTS pg_partman;       -- automated partition management
CREATE EXTENSION IF NOT EXISTS pg_repack;        -- online table/index bloat removal
CREATE EXTENSION IF NOT EXISTS pglogical;        -- logical replication (needs wal_level = logical)
CREATE EXTENSION IF NOT EXISTS wal2json;         -- logical decoding output plugin (no CREATE needed; used by slots)
CREATE EXTENSION IF NOT EXISTS pg_hint_plan;     -- plan hints in /*+ ... */ comments
```

`pg_hint_plan` only works when preloaded: add it to `shared_preload_libraries`.
`pglogical` and `wal2json` for logical replication need `wal_level = logical` (restart required).

### 5.9 Verify installed extensions

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
ORDER BY name;
```
