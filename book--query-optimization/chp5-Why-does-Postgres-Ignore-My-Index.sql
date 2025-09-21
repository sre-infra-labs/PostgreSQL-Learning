--alter role postgres set search_path to postgres_air;

set search_path to postgres_air;

select max(update_ts) from postgres_air.boarding_pass_large
-- 2023-11-12 21:56:43.46788+05:30

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select * from postgres_air.boarding_pass_large
where update_ts::date between '2023-11-05' and '2023-11-12'
limit 100;

/*  Optimizer chooses Seq Scan on table due to non-SARGable arguments

Limit  (cost=0.00..606.19 rows=100 width=40) (actual time=1524.784..8398.180 rows=3 loops=1)
  Output: pass_id, passenger_id, booking_leg_id, seat, boarding_time, precheck, update_ts
  Buffers: shared hit=64 read=782209
  ->  Seq Scan on postgres_air.boarding_pass_large  (cost=0.00..2299882.44 rows=379402 width=40) (actual time=1524.783..8398.176 rows=3 loops=1)
        Output: pass_id, passenger_id, booking_leg_id, seat, boarding_time, precheck, update_ts
        Filter: (((boarding_pass_large.update_ts)::date >= '2023-11-05'::date) AND ((boarding_pass_large.update_ts)::date <= '2023-11-12'::date))
        Rows Removed by Filter: 75880470
        Buffers: shared hit=64 read=782209
Planning:
  Buffers: shared hit=10 read=1
Planning Time: 0.146 ms
Execution Time: 8398.193 ms
*/


EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select * from postgres_air.boarding_pass_large
--where update_ts between '2023-08-05' and '2023-11-13'
where update_ts::date between '2023-11-05' and '2023-11-13'
limit 100;

/* Optimizer chooses Seq Scan on table
** This Seq Scan is result of the combination of relatilvely high selectivity of this index on this large table, and presence of the LIMIT operator.

Limit  (cost=0.00..606.19 rows=100 width=40) (actual time=1525.901..8337.450 rows=3 loops=1)
  Output: pass_id, passenger_id, booking_leg_id, seat, boarding_time, precheck, update_ts
  Buffers: shared hit=96 read=782177
  ->  Seq Scan on postgres_air.boarding_pass_large  (cost=0.00..2299882.44 rows=379402 width=40) (actual time=1525.900..8337.446 rows=3 loops=1)
        Output: pass_id, passenger_id, booking_leg_id, seat, boarding_time, precheck, update_ts
        Filter: (((boarding_pass_large.update_ts)::date >= '2023-11-05'::date) AND ((boarding_pass_large.update_ts)::date <= '2023-11-13'::date))
        Rows Removed by Filter: 75880470
        Buffers: shared hit=96 read=782177
Planning Time: 0.064 ms
Execution Time: 8337.464 ms
*/


EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select * from postgres_air.boarding_pass_large
where update_ts between '2023-11-05' and '2023-11-12'
order by 1
--order by update_ts
limit 100;

/* Optimizer chooses Bitmap Index Scan

Limit  (cost=172635.31..172635.56 rows=100 width=40) (actual time=1.924..1.925 rows=0 loops=1)
  Output: pass_id, passenger_id, booking_leg_id, seat, boarding_time, precheck, update_ts
  Buffers: shared hit=4
  ->  Sort  (cost=172635.31..172770.70 rows=54157 width=40) (actual time=0.011..0.012 rows=0 loops=1)
        Output: pass_id, passenger_id, booking_leg_id, seat, boarding_time, precheck, update_ts
        Sort Key: boarding_pass_large.pass_id
        Sort Method: quicksort  Memory: 25kB
        Buffers: shared hit=4
        ->  Bitmap Heap Scan on postgres_air.boarding_pass_large  (cost=991.68..170565.47 rows=54157 width=40) (actual time=0.006..0.007 rows=0 loops=1)
              Output: pass_id, passenger_id, booking_leg_id, seat, boarding_time, precheck, update_ts
              Recheck Cond: ((boarding_pass_large.update_ts >= '2023-11-05 00:00:00+05:30'::timestamp with time zone) AND (boarding_pass_large.update_ts <= '2023-11-12 00:00:00+05:30'::timestamp with time zone))
              Buffers: shared hit=4
              ->  Bitmap Index Scan on boarding_pass_large__update_ts  (cost=0.00..978.14 rows=54157 width=0) (actual time=0.005..0.005 rows=0 loops=1)
                    Index Cond: ((boarding_pass_large.update_ts >= '2023-11-05 00:00:00+05:30'::timestamp with time zone) AND (boarding_pass_large.update_ts <= '2023-11-12 00:00:00+05:30'::timestamp with time zone))
                    Buffers: shared hit=4
Planning:
  Buffers: shared hit=5 read=5
Planning Time: 0.140 ms
JIT:
  Functions: 3
  Options: Inlining false, Optimization false, Expressions true, Deforming true
  Timing: Generation 0.255 ms, Inlining 0.000 ms, Optimization 0.142 ms, Emission 1.768 ms, Total 2.165 ms
Execution Time: 2.212 ms
*/

