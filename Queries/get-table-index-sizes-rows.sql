/* All elements sizes */
select  pg_namespace.nspname as schema_name,
        case when idx_tbl.relkind = 'r' then idx_tbl.relname else tbl.relname end as table_name,
        --idx_tbl.relkind as type,
        case when idx_tbl.relkind = 'i' then idx_tbl.relname else null end as idx_name,
        pg_size_pretty(pg_relation_size(idx_tbl.oid)) as size,
        TO_CHAR(idx_tbl.reltuples, 'FM999,999,999,999') AS rows,
        pg_get_indexdef(idx_tbl.oid) as index_def
from pg_catalog.pg_class as idx_tbl
join pg_catalog.pg_namespace on relnamespace = pg_catalog.pg_namespace.oid
left join pg_catalog.pg_index as idx on idx.indexrelid = idx_tbl.oid and idx_tbl.relkind = 'i'
left join pg_catalog.pg_class as tbl on tbl.relkind = 'r' and idx.indrelid = tbl.oid
where pg_catalog.pg_namespace.nspname not in ('pg_catalog','pg_toast','information_schema')
--and idx_tbl.relname like 'users%'
order by table_name, idx_tbl.relkind desc, idx_tbl.relname desc;

