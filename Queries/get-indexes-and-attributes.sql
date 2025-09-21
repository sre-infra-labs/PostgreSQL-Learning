
/* Get Indexes & Attributes */
SELECT
        --U.usename                AS user_name,
        ns.nspname               AS schema_name,
        idx.indrelid :: REGCLASS AS table_name,
        --t.relname                 as table_name2,
        i.relname                AS index_name,
        idx.indisunique          AS is_unique,
        idx.indisprimary         AS is_primary,
        am.amname                AS index_type,
        --idx.indkey,
            ARRAY(
                SELECT pg_get_indexdef(idx.indexrelid, k + 1, TRUE)
                FROM
                    generate_subscripts(idx.indkey, 1) AS k
                ORDER BY k
            ) AS index_keys,
        (idx.indexprs IS NOT NULL) OR (idx.indkey::int[] @> array[0]) AS is_functional,
        idx.indpred IS NOT NULL AS is_partial
FROM pg_index AS idx
JOIN pg_class AS i ON i.oid = idx.indexrelid
JOIN pg_class AS t on t.oid = idx.indrelid
JOIN pg_am AS am ON i.relam = am.oid
JOIN pg_namespace AS NS ON i.relnamespace = NS.OID
JOIN pg_user AS U ON i.relowner = U.usesysid
WHERE 1=1
and nspname = 'public' -- Excluding system tables
and t.relname in ('posts') 
LIMIT 20;

