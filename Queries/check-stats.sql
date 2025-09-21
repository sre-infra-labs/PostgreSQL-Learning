select *
from pg_stats
where schemaname = 'public' and tablename = 'posts'

select *
from pg_extensions