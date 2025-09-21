set search_path to postgres_air;

explain analyze
select *
from account
where lower(last_name) = 'daniels';

/*
Indexes:
    "account_pkey" PRIMARY KEY, btree (account_id)
    "account_last_name" btree (last_name)

Gather  (cost=1000.00..15110.51 rows=4325 width=53) (actual time=1.334..360.277 rows=764 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  ->  Parallel Seq Scan on account  (cost=0.00..13678.01 rows=1802 width=53) (actual time=1.464..247.962 rows=255 loops=3)
        Filter: (lower(last_name) = 'daniels'::text)
        Rows Removed by Filter: 288066
Planning Time: 4.250 ms
Execution Time: 360.626 ms
*/

-- create functional index
create index account_last_name_lower on account (lower(last_name));

explain analyze
select *
from account
where lower(last_name) = 'daniels';

/*
Indexes:
    "account_pkey" PRIMARY KEY, btree (account_id)
    "account_last_name" btree (last_name)
    "account_last_name_lower" btree (lower(last_name))


Bitmap Heap Scan on account  (cost=49.94..7207.63 rows=4325 width=53) (actual time=0.442..6.829 rows=764 loops=1)
  Recheck Cond: (lower(last_name) = 'daniels'::text)
  Heap Blocks: exact=695
  ->  Bitmap Index Scan on account_last_name_lower  (cost=0.00..48.86 rows=4325 width=0) (actual time=0.250..0.250 rows=764 loops=1)
        Index Cond: (lower(last_name) = 'daniels'::text)
Planning Time: 1.680 ms
Execution Time: 6.926 ms
*/

