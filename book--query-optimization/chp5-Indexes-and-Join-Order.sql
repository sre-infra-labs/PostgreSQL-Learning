set search_path to postgres_air;

/* Concept:
** In Short queries, the optimization goal is to avoid large intermediate results.
** That means ensuring that the most restrictive selection criteria are applied first.
** After that, for each join operation, we should ensure that the results continue to be small
**
** The size of join results may be small either because of restrictions on the joined tables or because of a semi-join.
*/  

CREATE INDEX account_login ON account(login);
CREATE INDEX account_login_lower_pattern ON account (lower(login) text_pattern_ops);
CREATE INDEX passenger_last_name ON passenger (last_name);
CREATE INDEX boarding_pass_passenger_id ON boarding_pass (passenger_id);
CREATE INDEX passenger_last_name_lower_pattern ON passenger (lower(last_name) text_pattern_ops);
CREATE INDEX passenger_booking_id ON passenger(booking_id);
CREATE INDEX booking_account_id ON booking(account_id);
create index passenger_last_name_lower on passenger (lower(last_name)); -- Ajay

/* Listing 5-13: Order of joins example
** Execution plan chooses account table as starting point as the filter condition is slightly better in selectivity compared to passenger
** 
** Order of joins: execution starts from smaller table, when selecitity is similar
** In order words, it is the selectivity of filter predicate that matters
*/
explain analyze
SELECT b.account_id,
    a.login,
    p.last_name,
    p.first_name
FROM passenger p
JOIN booking b USING(booking_id)
JOIN account a ON a.account_id=b.account_id
WHERE lower(p.last_name)='smith'
AND lower(a.login) LIKE 'smith%';

select p.booking_id, p.last_name, p.first_name from passenger p where lower(p.last_name) = 'smith';
-- (426,974 row(s) affected)
select a.login, a.account_id from account a where lower(a.login) LIKE 'smith%';
-- (6195 row(s) affected)

/*
Gather  (cost=1145.62..81186.60 rows=408 width=41) (actual time=3.386..1162.959 rows=36489 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  ->  Nested Loop  (cost=145.62..80145.80 rows=170 width=41) (actual time=1.539..1056.252 rows=12163 loops=3)
        ->  Nested Loop  (cost=145.19..70853.64 rows=11757 width=37) (actual time=1.196..318.233 rows=11601 loops=3)
              ->  Parallel Bitmap Heap Scan on account a  (cost=144.76..7264.60 rows=1802 width=29) (actual time=0.842..60.584 rows=2065 loops=3)
                    Filter: (lower(login) ~~ 'smith%'::text)
                    Heap Blocks: exact=1106
                    ->  Bitmap Index Scan on account_login_lower_pattern  (cost=0.00..143.68 rows=4325 width=0) (actual time=1.853..1.854 rows=6195 loops=1)
                          Index Cond: ((lower(login) ~>=~ 'smith'::text) AND (lower(login) ~<~ 'smiti'::text))
              ->  Index Scan using booking_account_id on booking b  (cost=0.43..35.19 rows=10 width=12) (actual time=0.031..0.122 rows=6 loops=6195)
                    Index Cond: (account_id = a.account_id)
        ->  Index Scan using passenger_booking_id on passenger p  (cost=0.43..0.78 rows=1 width=16) (actual time=0.052..0.063 rows=1 loops=34802)
              Index Cond: (booking_id = b.booking_id)
              Filter: (lower(last_name) = 'smith'::text)
              Rows Removed by Filter: 2
Planning Time: 3.632 ms
Execution Time: 1165.706 ms
*/





/* Listing 5-13: Order of joins example
** Execution plan chooses passenger table as entry point as the filter condition is slightly better in selectivity compared to account
** 
** Order of joins: execution starts from smaller table, when selecitity is similar
** In order words, it is the selectivity of filter predicate that matters
*/
explain analyze
SELECT b.account_id,
    a.login,
    p.last_name,
    p.first_name
FROM passenger p
JOIN booking b USING(booking_id)
JOIN account a ON a.account_id=b.account_id
WHERE lower(p.last_name)='bourne'
AND lower(a.login) LIKE 'smith%';


select p.booking_id, p.last_name, p.first_name from passenger p where lower(p.last_name) = 'smith';
-- (426,974 row(s) affected)
select p.booking_id, p.last_name, p.first_name from passenger p where lower(p.last_name) = 'bourne';
-- (1520  row(s) affected)
select p.booking_id, p.last_name, p.first_name from passenger p where lower(p.last_name) = 'foryth';
-- (0 row(s) affected)
select a.login, a.account_id from account a where lower(a.login) LIKE 'smith%';
-- (6195 row(s) affected)

ANALYZE VERBOSE;
VACUUM ANALYZE ;

/*
Gather  (cost=1078.10..46713.10 rows=69 width=41) (actual time=332.569..389.015 rows=7 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  ->  Nested Loop  (cost=78.10..45706.20 rows=29 width=41) (actual time=138.226..262.190 rows=2 loops=3)
        ->  Nested Loop  (cost=77.68..44414.34 rows=2839 width=16) (actual time=1.121..173.437 rows=507 loops=3)
              ->  Parallel Bitmap Heap Scan on passenger p  (cost=77.24..22892.98 rows=2839 width=16) (actual time=0.289..3.757 rows=507 loops=3)
                    Recheck Cond: (lower(last_name) = 'bourne'::text)
                    Heap Blocks: exact=650
                    ->  Bitmap Index Scan on passenger_last_name_lower  (cost=0.00..75.54 rows=6814 width=0) (actual time=0.506..0.507 rows=1520 loops=1)
                          Index Cond: (lower(last_name) = 'bourne'::text)
              ->  Index Scan using booking_pkey on booking b  (cost=0.43..7.58 rows=1 width=12) (actual time=0.331..0.331 rows=1 loops=1520)
                    Index Cond: (booking_id = p.booking_id)
        ->  Index Scan using account_pkey on account a  (cost=0.42..0.46 rows=1 width=29) (actual time=0.173..0.173 rows=0 loops=1520)
              Index Cond: (account_id = b.account_id)
              Filter: (lower(login) ~~ 'smith%'::text)
              Rows Removed by Filter: 1
Planning Time: 0.756 ms
Execution Time: 389.100 ms
*/


/* Listing 5-14:
** 
*/
CREATE INDEX frequent_fl_last_name_lower_pattern ON frequent_flyer (lower(last_name) text_pattern_ops);
CREATE INDEX frequent_fl_last_name_lower ON frequent_flyer (lower(last_name));

EXPLAIN ANALYZE
SELECT a.account_id,
    a.login,
    f.last_name,
    f.first_name,
count(*) AS num_bookings
FROM frequent_flyer f
JOIN account a USING(frequent_flyer_id)
JOIN booking b USING(account_id)
WHERE lower(f.last_name)='smith'
AND lower(login) LIKE 'smith%'
GROUP BY 1,2,3,4;

/*
GroupAggregate  (cost=10467.65..10474.10 rows=287 width=49) (actual time=268.402..273.676 rows=1832 loops=1)
  Group Key: a.account_id, f.last_name, f.first_name
  ->  Sort  (cost=10467.65..10468.36 rows=287 width=41) (actual time=268.387..269.294 rows=15404 loops=1)
        Sort Key: a.account_id, f.last_name, f.first_name
        Sort Method: quicksort  Memory: 1387kB
        ->  Nested Loop  (cost=1586.33..10455.93 rows=287 width=41) (actual time=86.917..259.146 rows=15404 loops=1)
              ->  Hash Join  (cost=1585.90..10315.07 rows=44 width=41) (actual time=86.554..177.826 rows=1832 loops=1)
                    Hash Cond: (a.frequent_flyer_id = f.frequent_flyer_id)
                    ->  Bitmap Heap Scan on account a  (cost=288.25..8994.49 rows=8737 width=33) (actual time=1.392..169.908 rows=6195 loops=1)
                          Filter: (lower(login) ~~ 'smith%'::text)
                          Heap Blocks: exact=3021
                          ->  Bitmap Index Scan on account_login_lower_pattern  (cost=0.00..286.06 rows=8564 width=0) (actual time=0.865..0.866 rows=6195 loops=1)
                                Index Cond: ((lower(login) ~>=~ 'smith'::text) AND (lower(login) ~<~ 'smiti'::text))
                    ->  Hash  (cost=1289.63..1289.63 rows=642 width=16) (actual time=5.154..5.155 rows=3418 loops=1)
                          Buckets: 4096 (originally 1024)  Batches: 1 (originally 1)  Memory Usage: 197kB
                          ->  Bitmap Heap Scan on frequent_flyer f  (cost=9.27..1289.63 rows=642 width=16) (actual time=0.523..4.324 rows=3418 loops=1)
                                Recheck Cond: (lower(last_name) = 'smith'::text)
                                Heap Blocks: exact=1525
                                ->  Bitmap Index Scan on frequent_fl_last_name_lower  (cost=0.00..9.11 rows=642 width=0) (actual time=0.315..0.316 rows=3418 loops=1)
                                      Index Cond: (lower(last_name) = 'smith'::text)
              ->  Index Only Scan using booking_account_id on booking b  (cost=0.43..3.10 rows=10 width=4) (actual time=0.041..0.043 rows=8 loops=1832)
                    Index Cond: (account_id = a.account_id)
                    Heap Fetches: 0
Planning Time: 2.751 ms
Execution Time: 274.341 ms
*/
