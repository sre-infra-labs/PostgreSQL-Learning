# Troubleshooting cpu/memory/disk issues
- https://www.cybertec-postgresql.com/en/find-and-fix-a-missing-postgresql-index/
- https://www.postgresql.org/docs/current/pgstatstatements.html#PGSTATSTATEMENTS

# Top 5 long running queries
```
SELECT round((100 * total_exec_time / sum(total_exec_time)
        OVER ())::numeric, 2) percent,
        round(total_exec_time::numeric, 2) AS total,
        calls,
        round(mean_exec_time::numeric, 2) AS mean,
        substring(query, 1, 200)
 FROM  pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 5;
```

# Top 3 CPU consumers
```
SELECT
    -- Sum of execution time and planning time is the best proxy for total CPU usage
    round((total_exec_time + total_plan_time)::numeric, 2) AS total_cpu_time_ms,
    calls,
    -- CORRECTED LINE: Cast the result of the division to numeric before rounding
    round(((total_exec_time + total_plan_time) / calls::numeric)::numeric, 2) AS avg_cpu_time_ms,
    -- Calculate the percentage of total CPU time this query consumed
    round((100 * (total_exec_time + total_plan_time) / sum(total_exec_time + total_plan_time) OVER ())::numeric, 2) AS percent_of_total_time,
    query
FROM
    pg_stat_statements
ORDER BY
    total_cpu_time_ms DESC
LIMIT 3;
```

# Top Queries by Total I/O Time
```
SELECT
	datname,
    -- Sum of blocks read from disk and blocks dirtied (to be written)
    (shared_blks_read + shared_blks_dirtied) AS total_disk_io_blocks,
    calls,
    round((shared_blks_read + shared_blks_dirtied) / calls::numeric, 2) AS avg_io_blocks_per_call,
    -- Cache Hit Ratio (higher is better)
    round(
        shared_blks_hit::numeric * 100 / NULLIF(shared_blks_hit + shared_blks_read, 0),
        2
    ) AS cache_hit_percent,
    query
FROM
    pg_stat_statements ss join pg_database d on d.oid = ss.dbid
ORDER BY
    --total_disk_io_blocks DESC
	avg_io_blocks_per_call desc
LIMIT 50;
```


# Top Queries by Blocks Accessed (I/O Volume)
```
SELECT
    -- Sum of blocks read from disk and blocks dirtied (to be written)
    (shared_blks_read + shared_blks_dirtied) AS total_disk_io_blocks,
    calls,
    round((shared_blks_read + shared_blks_dirtied) / calls::numeric, 2) AS avg_io_blocks_per_call,
    -- Cache Hit Ratio (higher is better)
    round(
        shared_blks_hit::numeric * 100 / NULLIF(shared_blks_hit + shared_blks_read, 0),
        2
    ) AS cache_hit_percent,
    query
FROM
    pg_stat_statements
ORDER BY
    total_disk_io_blocks DESC
LIMIT 5;
```

# Top 5 Memory-Consuming Queries
```
SELECT
    query,
    calls,
    temp_blks_written,
    shared_blks_read,
    -- Calculate a score, prioritizing temporary block writes (spilling to disk)
    (temp_blks_written * 10) + shared_blks_read AS memory_score
FROM
    pg_stat_statements
ORDER BY
    memory_score DESC
LIMIT 5;
```

# 


