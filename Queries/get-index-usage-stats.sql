/*      https://sgerogia.github.io/Postgres-Index-And-Queries/
        https://www.timescale.com/learn/postgresql-performance-tuning-optimizing-database-indexes
        https://www.cybertec-postgresql.com/en/find-and-fix-a-missing-postgresql-index/
*/

select * from check_indexes('public', 'posts');

-- https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ALL-TABLES-VIEW
SELECT 'pg_stat_all_tables' as "RunningQuery", r.schemaname, r.relname, pg_size_pretty(pg_relation_size(relid)) AS rel_size, r.seq_scan,
        r.seq_tup_read, r.idx_scan, r.idx_tup_fetch, r.n_tup_ins, r.n_tup_upd, r.n_tup_del,
        r.n_tup_hot_upd, r.n_tup_newpage_upd, r.n_live_tup, r.n_dead_tup, r.n_ins_since_vacuum,
        r.n_mod_since_analyze
FROM pg_stat_all_tables r
where r.schemaname = 'public' and r.relname = 'posts'
limit 10;

-- https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STATIO-ALL-TABLES-VIEW
select 'pg_statio_all_tables' as "RunningQuery", tio.schemaname, tio.relname, tio.heap_blks_read, tio.heap_blks_hit, tio.idx_blks_read, tio.idx_blks_hit,
        tio.toast_blks_hit, tio.toast_blks_hit
from pg_statio_all_tables tio
where tio.schemaname = 'public' and tio.relname = 'posts';

-- https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ALL-INDEXES-VIEW
select *
from pg_stat_all_indexes i
where i.schemaname = 'public' and i.relname = 'posts' -- and i.indexrelname = 'posts_owneruserid'
limit 10;

-- https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STATIO-ALL-TABLES-VIEW
select *
from pg_statio_all_indexes iio
where iio.schemaname = 'public' and iio.relname = 'posts';