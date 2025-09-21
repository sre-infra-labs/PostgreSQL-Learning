-- Find Table/Index Usage
  -- https://github.com/SmartPostgres/Box-of-Tricks/blob/dev/checks/check_indexes.sql
select * from check_indexes('public', NULL);
select * from check_indexes('public','users');

-- Find cardinality of index
SELECT schema_name,
       object_name,
       object_type,
       cardinality,
       pages
FROM (
       SELECT pg_catalog.pg_namespace.nspname AS schema_name,
              relname                         as object_name,
              relkind                         as object_type,
              reltuples                       as cardinality,
              relpages                        as pages
       FROM pg_catalog.pg_class
              JOIN pg_catalog.pg_namespace ON relnamespace = pg_catalog.pg_namespace.oid
     ) t
WHERE schema_name NOT LIKE 'pg_%'
  and schema_name <> 'information_schema'
  --and schema_name = '$schema_name'
  --and object_name = '$object_name'
ORDER BY pages DESC, schema_name, object_name
;