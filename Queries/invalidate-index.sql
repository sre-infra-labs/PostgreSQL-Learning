/*  Invalidate an Index 
    This this superuser permissions on cluster as it modified pg_catalog system schema.
*/
update pg_index set indisvalid = false
where indexrelid = (
    select oid
    from pg_class
    where relkind = 'i'
    and relname = 'posts_score_tags'
);

