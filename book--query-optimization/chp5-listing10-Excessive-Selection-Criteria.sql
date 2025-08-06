set
    search_path to postgres_air;

/* Query 01: Query with conditions on two tables
** Optimization making good choice to merge 2 flight_scheduled_departure filters 
*/
--explain ANALYZE
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT
    last_name,
    first_name,
    seat
FROM
    boarding_pass bp
    JOIN booking_leg bl USING (booking_leg_id)
    JOIN flight f USING (flight_id)
    JOIN booking b USING(booking_id)
    JOIN passenger p USING (passenger_id)
WHERE
    (
        departure_airport = 'JFK'
        AND scheduled_departure BETWEEN '2020-07-10' AND '2020-07-11'
        AND last_name = 'JOHNSON'
    )
    OR (
        departure_airport = 'EDW'
        AND scheduled_departure BETWEEN '2020-07-13' AND '2020-07-14'
        AND last_name = 'JOHNSTON'
    );

/*
Nested Loop  (cost=15.25..1034.63 rows=1 width=15) (actual time=0.013..0.015 rows=0 loops=1)
  ->  Nested Loop  (cost=14.82..1033.27 rows=1 width=19) (actual time=0.013..0.014 rows=0 loops=1)
        Join Filter: (((f.departure_airport = 'JFK'::bpchar) AND (f.scheduled_departure >= '2020-07-10 00:00:00+05:30'::timestamp with time zone) AND (f.scheduled_departure <= '2020-07-11 00:00:00+05:30'::timestamp with time zone) AND (p.last_name = 'JOHNSON'::text)) OR ((f.departure_airport = 'EDW'::bpchar) AND (f.scheduled_departure >= '2020-07-13 00:00:00+05:30'::timestamp with time zone) AND (f.scheduled_departure <= '2020-07-14 00:00:00+05:30'::timestamp with time zone) AND (p.last_name = 'JOHNSTON'::text)))
        ->  Nested Loop  (cost=14.38..938.48 rows=37 width=27) (actual time=0.012..0.013 rows=0 loops=1)
              ->  Nested Loop  (cost=13.94..341.67 rows=26 width=20) (actual time=0.012..0.013 rows=0 loops=1)
                    ->  Bitmap Heap Scan on flight f  (cost=8.87..12.90 rows=1 width=16) (actual time=0.012..0.013 rows=0 loops=1)
                          Recheck Cond: (((scheduled_departure >= '2020-07-10 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2020-07-11 00:00:00+05:30'::timestamp with time zone)) OR ((scheduled_departure >= '2020-07-13 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2020-07-14 00:00:00+05:30'::timestamp with time zone)))
                          Filter: (((departure_airport = 'JFK'::bpchar) AND (scheduled_departure >= '2020-07-10 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2020-07-11 00:00:00+05:30'::timestamp with time zone)) OR ((departure_airport = 'EDW'::bpchar) AND (scheduled_departure >= '2020-07-13 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2020-07-14 00:00:00+05:30'::timestamp with time zone)))
                          ->  BitmapOr   (cost=8.87..8.87 rows=1 width=0) (actual time=0.011..0.011 rows=0 loops=1)
                                ->  Bitmap Index Scan on flight_scheduled_departure  (cost=0.00..4.43 rows=1 width=0) (actual time=0.008..0.008 rows=0 loops=1)
                                      Index Cond: ((scheduled_departure >= '2020-07-10 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2020-07-11 00:00:00+05:30'::timestamp with time zone))
                                ->  Bitmap Index Scan on flight_scheduled_departure  (cost=0.00..4.43 rows=1 width=0) (actual time=0.002..0.002 rows=0 loops=1)
                                      Index Cond: ((scheduled_departure >= '2020-07-13 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2020-07-14 00:00:00+05:30'::timestamp with time zone))
                    ->  Bitmap Heap Scan on booking_leg bl  (cost=5.07..327.96 rows=82 width=12) (never executed)
                          Recheck Cond: (flight_id = f.flight_id)
                          ->  Bitmap Index Scan on booking_leg_flight_id  (cost=0.00..5.05 rows=82 width=0) (never executed)
                                Index Cond: (flight_id = f.flight_id)
              ->  Index Scan using boarding_pass_booking_leg_id on boarding_pass bp  (cost=0.44..22.72 rows=23 width=19) (never executed)
                    Index Cond: (booking_leg_id = bl.booking_leg_id)
        ->  Index Scan using passenger_pkey on passenger p  (cost=0.43..2.53 rows=1 width=16) (never executed)
              Index Cond: (passenger_id = bp.passenger_id)
              Filter: ((last_name = 'JOHNSON'::text) OR (last_name = 'JOHNSTON'::text))
  ->  Index Only Scan using booking_pkey on booking b  (cost=0.43..1.35 rows=1 width=8) (never executed)
        Index Cond: (booking_id = bl.booking_id)
        Heap Fetches: 0
Planning Time: 1.780 ms
Execution Time: 0.369 ms
*/


/* Query listing 5-11: short query with hard-to-optimize filtering 
** This query looks for flights that were more than one hour delayed (of which there should not be many). 
** For all of these delayed flights, the query selects boarding passes issued after the scheduled departure.
**
**
*/
explain ANALYZE
--EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT bp.update_ts Boarding_pass_issued,
       scheduled_departure,
       actual_departure,
       status
FROM flight f
JOIN booking_leg bl USING (flight_id)
JOIN boarding_pass bp USING (booking_leg_id)
WHERE bp.update_ts > scheduled_departure + interval '30 minutes'
AND f.update_ts >=scheduled_departure -interval '1 hour';
/*
Gather  (cost=288845.90..1130658.34 rows=2810462 width=35) (actual time=2723.622..3513.826 rows=99 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  ->  Parallel Hash Join  (cost=287845.90..848612.14 rows=1171026 width=35) (actual time=2702.528..3257.865 rows=33 loops=3)
        Hash Cond: (bp.booking_leg_id = bl.booking_leg_id)
        Join Filter: (bp.update_ts > (f.scheduled_departure + '00:30:00'::interval))
        Rows Removed by Join Filter: 2430401
        ->  Parallel Seq Scan on boarding_pass bp  (cost=0.00..366200.33 rows=10539233 width=16) (actual time=0.039..677.406 rows=8431164 loops=3)
        ->  Parallel Hash  (cost=239791.67..239791.67 rows=2485218 width=31) (actual time=1097.220..1097.222 rows=848757 loops=3)
              Buckets: 131072  Batches: 64  Memory Usage: 3552kB
              ->  Parallel Hash Join  (cost=14079.94..239791.67 rows=2485218 width=31) (actual time=194.027..966.345 rows=848757 loops=3)
                    Hash Cond: (bl.flight_id = f.flight_id)
                    ->  Parallel Seq Scan on booking_leg bl  (cost=0.00..206140.53 rows=7455652 width=8) (actual time=0.018..365.407 rows=5964522 loops=3)
                    ->  Parallel Hash  (cost=12893.86..12893.86 rows=94886 width=31) (actual time=193.480..193.481 rows=28064 loops=3)
                          Buckets: 262144  Batches: 1  Memory Usage: 7360kB
                          ->  Parallel Seq Scan on flight f  (cost=0.00..12893.86 rows=94886 width=31) (actual time=172.571..188.941 rows=28064 loops=3)
                                Filter: (update_ts >= (scheduled_departure - '01:00:00'::interval))
                                Rows Removed by Filter: 199662
Planning Time: 0.281 ms
JIT:
  Functions: 69
  Options: Inlining true, Optimization true, Expressions true, Deforming true
  Timing: Generation 2.591 ms, Inlining 88.147 ms, Optimization 264.196 ms, Emission 165.361 ms, Total 520.295 ms
Execution Time: 3514.653 ms
*/



/* Query listing 5-12: Query with added excessive selection criteria
**
**
*/
CREATE INDEX boarding_pass_update_ts ON postgres_air.boarding_pass  (update_ts);


explain ANALYZE
--EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT bp.update_ts Boarding_pass_issued,
       scheduled_departure,
       actual_departure,
       status
FROM flight f
JOIN booking_leg bl USING (flight_id)
JOIN boarding_pass bp USING (booking_leg_id)
WHERE bp.update_ts  > scheduled_departure + interval '30 minutes'
AND f.update_ts >=scheduled_departure -interval '1 hour'
AND bp.update_ts >='2020-08-16' AND bp.update_ts< '2020-08-20'
/*
Nested Loop  (cost=1.30..17.38 rows=1 width=35) (actual time=0.004..0.004 rows=0 loops=1)
  Join Filter: (bp.update_ts > (f.scheduled_departure + '00:30:00'::interval))
  ->  Nested Loop  (cost=0.88..16.91 rows=1 width=12) (actual time=0.004..0.004 rows=0 loops=1)
        ->  Index Scan using boarding_pass_update_ts on boarding_pass bp  (cost=0.44..8.46 rows=1 width=16) (actual time=0.003..0.004 rows=0 loops=1)
              Index Cond: ((update_ts >= '2020-08-16 00:00:00+05:30'::timestamp with time zone) AND (update_ts < '2020-08-20 00:00:00+05:30'::timestamp with time zone))
        ->  Index Scan using booking_leg_pkey on booking_leg bl  (cost=0.44..8.46 rows=1 width=8) (never executed)
              Index Cond: (booking_leg_id = bp.booking_leg_id)
  ->  Index Scan using flight_pkey on flight f  (cost=0.42..0.45 rows=1 width=31) (never executed)
        Index Cond: (flight_id = bl.flight_id)
        Filter: (update_ts >= (scheduled_departure - '01:00:00'::interval))
Planning Time: 0.481 ms
Execution Time: 0.021 ms
*/