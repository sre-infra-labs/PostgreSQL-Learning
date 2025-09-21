set search_path to postgres_air;

explain ANALYZE
select *
from account
where lower(last_name) like 'johns%';

/*
Indexes:
    "account_pkey" PRIMARY KEY, btree (account_id)
    "account_last_name" btree (last_name)
    "account_last_name_lower" btree (lower(last_name))

Gather  (cost=1000.00..15110.51 rows=4325 width=53) (actual time=1.152..189.618 rows=8380 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  ->  Parallel Seq Scan on account  (cost=0.00..13678.01 rows=1802 width=53) (actual time=0.256..135.537 rows=2793 loops=3)
        Filter: (lower(last_name) ~~ 'johns%'::text)
        Rows Removed by Filter: 285527
Planning Time: 0.112 ms
Execution Time: 189.971 ms
*/

explain ANALYZE
select *
from account
where lower(last_name) >= 'johns' and lower(last_name) < 'johnt';

/*
Indexes:
    "account_pkey" PRIMARY KEY, btree (account_id)
    "account_last_name" btree (last_name)
    "account_last_name_lower" btree (lower(last_name))

Bitmap Heap Scan on account  (cost=60.76..7240.07 rows=4325 width=53) (actual time=1.022..6.026 rows=8380 loops=1)
  Recheck Cond: ((lower(last_name) >= 'johns'::text) AND (lower(last_name) < 'johnt'::text))
  Heap Blocks: exact=5217
  ->  Bitmap Index Scan on account_last_name_lower  (cost=0.00..59.67 rows=4325 width=0) (actual time=0.579..0.579 rows=8380 loops=1)
        Index Cond: ((lower(last_name) >= 'johns'::text) AND (lower(last_name) < 'johnt'::text))
Planning Time: 0.102 ms
Execution Time: 6.297 ms

*/

-- create pattern index
create index account_last_name_lower_pattern on account (lower(last_name) text_pattern_ops);

explain ANALYZE
select *
from account
where lower(last_name) like 'johns%';

/*
Indexes:
    "account_pkey" PRIMARY KEY, btree (account_id)
    "account_last_name" btree (last_name)
    "account_last_name_lower" btree (lower(last_name))
    "account_last_name_lower_pattern" btree (lower(last_name) text_pattern_ops)
    

Bitmap Heap Scan on account  (cost=60.76..7218.44 rows=4325 width=53) (actual time=3.246..8.940 rows=8380 loops=1)
  Filter: (lower(last_name) ~~ 'johns%'::text)
  Heap Blocks: exact=5217
  ->  Bitmap Index Scan on account_last_name_lower_pattern  (cost=0.00..59.67 rows=4325 width=0) (actual time=1.891..1.891 rows=8380 loops=1)
        Index Cond: ((lower(last_name) ~>=~ 'johns'::text) AND (lower(last_name) ~<~ 'johnt'::text))
Planning Time: 15.460 ms
Execution Time: 9.256 ms
*/