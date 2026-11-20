## 2. Memory and resource settings

Put these in `conf.d/dba.conf` (or `postgresql.conf`). Starting points for a dedicated DB server; adjust to RAM:

```conf
shared_buffers = 4GB             # ~25% of RAM is a common starting point (requires restart)
work_mem = 64MB                  # per sort/hash operation, per connection; keep modest
maintenance_work_mem = 2GB       # VACUUM, CREATE INDEX, ALTER TABLE ADD FK
wal_buffers = -1                 # auto (1/32 of shared_buffers, max 16MB)
effective_cache_size = 12GB      # planner hint: RAM available for OS cache + shared_buffers
max_connections = 100            # keep low; use a pooler (pgbouncer) for many clients
```

Notes:
- `shared_buffers` and `max_connections` need a restart. `work_mem`, `maintenance_work_mem`, `effective_cache_size` only need a reload.
- `work_mem` is multiplied by concurrent sorts/hashes, so do not set it high globally. Raise it per session when needed: `SET work_mem = '256MB';`

Apply and verify:

```bash
sudo systemctl restart postgresql@18-main
```

```sql
SELECT name, setting, unit, source, sourcefile
FROM pg_settings
WHERE name IN ('shared_buffers','wal_buffers','work_mem','maintenance_work_mem','effective_cache_size','max_connections');
```

### 2.1 CPU and parallel query settings

These control how many background workers PostgreSQL may start and how many a single query or index build may use. Values below fit a server where PostgreSQL is limited to 4 CPUs (see 2.2). These settings do not restrict CPU use on their own; 2.2 does that.

```conf
max_worker_processes = 8                   # total background workers; keep above the parallel total + extensions (requires restart)
max_parallel_workers = 4                   # workers for parallel queries across all sessions; = CPUs allowed
max_parallel_workers_per_gather = 2        # workers per query node
max_parallel_maintenance_workers = 2       # workers for CREATE INDEX, VACUUM, etc.
```

Notes:
- `max_worker_processes` needs a restart. The `max_parallel_*` settings only need a reload.
- `max_parallel_workers` and `max_parallel_workers_per_gather` must not exceed `max_worker_processes`. Background workers started by extensions (for example pg_cron) also count toward `max_worker_processes`, so leave headroom.
- Raise parallelism for a heavy reporting session only, and only up to the CPUs allowed: `SET max_parallel_workers_per_gather = 4;`
- Leave `parallel_setup_cost` and `parallel_tuple_cost` at their defaults until `EXPLAIN (ANALYZE)` shows a real need to change them.

### 2.2 Restrict PostgreSQL to 4 CPUs (systemd)

Parallel settings cannot pin PostgreSQL to specific CPUs. Use systemd's `AllowedCPUs=` (cgroup v2, systemd 244+; this host has systemd 259 and cgroup v2). It applies to the whole cluster unit, so the postmaster, backends, autovacuum and background workers all stay on the chosen CPUs.

Check the CPU IDs first. `lscpu -e` lists them; with SMT, 4 logical CPUs may be only 2 physical cores. To use 4 physical cores, pick 4 distinct `CORE` values and their `CPU` IDs.

```bash
lscpu -e=CPU,CORE,SOCKET | head -20
```

Create a drop-in for the cluster unit (this host runs `postgresql@18-main.service`; the example uses CPUs `0-3`):

```bash
sudo mkdir -p /etc/systemd/system/postgresql@18-main.service.d
sudo tee /etc/systemd/system/postgresql@18-main.service.d/cpu-limit.conf > /dev/null <<'EOF'
[Service]
AllowedCPUs=0-3
# optional: cap CPU time at 4 CPUs' worth (400%); comment must match the value
CPUQuota=400%
EOF
sudo systemctl daemon-reload
sudo systemctl restart postgresql@18-main
```

Verify:

```bash
systemctl show postgresql@18-main -p AllowedCPUs
sudo taskset -cp "$(sudo head -1 /var/lib/postgresql/18/main/postmaster.pid)"   # expect: 0-3
cat /sys/fs/cgroup/system.slice/postgresql@18-main.service/cpuset.cpus.effective # expect: 0-3
```

Notes:
- Processes outside the unit are not limited. For example, pgBackRest run from cron as the `postgres` user, or a `psql` session you start from another shell, can use any CPU. Run long backups inside the same limit with `systemd-run --scope -p AllowedCPUs=0-3 ...` if needed.
- To undo, remove `cpu-limit.conf`, run `sudo systemctl daemon-reload`, and restart the cluster.
- `AllowedCPUs` chooses which CPUs are used. `CPUQuota` caps how much CPU time the cluster may use. They can be combined, as in the drop-in above.
- **Existing override on the wrapper unit:** `/etc/systemd/system/postgresql.service.d/override.conf` sets `CPUQuota=400%`, `MemoryHigh=6G` and `MemoryMax=12G` on `postgresql.service`. Those limits do not apply to the running cluster, because `postgresql@18-main.service` runs in its own cgroup under `system.slice`, not inside the wrapper's. Check with `systemctl show postgresql@18-main.service -p CPUQuotaPerSecUSec -p MemoryMax`, which shows `infinity` until the limits are moved. To apply them to the cluster, move those lines into `postgresql@18-main.service.d/cpu-limit.conf` (or a similar `memory-limit.conf`) and remove the wrapper override, so there is one source of truth.
- The existing override's comment says "Limit to 2 CPU cores" but `CPUQuota=400%` means 4 cores. Fix the comment or the value.

Verify:

```sql
SELECT name, setting, context, source
FROM pg_settings
WHERE name IN ('max_worker_processes','max_parallel_workers','max_parallel_workers_per_gather','max_parallel_maintenance_workers');
```
