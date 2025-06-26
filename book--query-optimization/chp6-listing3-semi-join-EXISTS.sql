set search_path to postgres_air;

/*
A semi-join is a special kind of join that satisfies two specific conditions: 

First, only columns from the first table appear in the result set.
Second, rows from the first table are not duplicated where there is more than one match in the second table. 

Most often, a semi-join doesn’t include a JOIN keyword at all.
*/

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT * FROM flight f WHERE EXISTS
  (SELECT flight_id FROM booking_leg WHERE flight_id=f.flight_id);
/*
Gather  (cost=1000.44..167432.76 rows=216673 width=71) (actual time=2.775..393.932 rows=508844 loops=1)
  Output: f.flight_id, f.flight_no, f.scheduled_departure, f.scheduled_arrival, f.departure_airport, f.arrival_airport, f.status, f.aircraft_code, f.actual_departure, f.actual_arrival, f.update_ts
  Workers Planned: 2
  Workers Launched: 2
  Buffers: shared hit=2131358 read=13440
  ->  Nested Loop Semi Join  (cost=0.44..144765.46 rows=90280 width=71) (actual time=3.290..352.946 rows=169615 loops=3)
        Output: f.flight_id, f.flight_no, f.scheduled_departure, f.scheduled_arrival, f.departure_airport, f.arrival_airport, f.status, f.aircraft_code, f.actual_departure, f.actual_arrival, f.update_ts
        Buffers: shared hit=2131358 read=13440
        Worker 0:  actual time=3.634..350.706 rows=168984 loops=1
          JIT:
            Functions: 4
            Options: Inlining false, Optimization false, Expressions true, Deforming true
            Timing: Generation 0.335 ms, Inlining 0.000 ms, Optimization 0.198 ms, Emission 3.364 ms, Total 3.896 ms
          Buffers: shared hit=708246 read=4087
        Worker 1:  actual time=3.642..350.754 rows=168966 loops=1
          JIT:
            Functions: 4
            Options: Inlining false, Optimization false, Expressions true, Deforming true
            Timing: Generation 0.334 ms, Inlining 0.000 ms, Optimization 0.198 ms, Emission 3.364 ms, Total 3.895 ms
          Buffers: shared hit=706604 read=4099
        ->  Parallel Seq Scan on postgres_air.flight f  (cost=0.00..11470.58 rows=284658 width=71) (actual time=0.012..17.407 rows=227726 loops=3)
              Output: f.flight_id, f.flight_no, f.scheduled_departure, f.scheduled_arrival, f.departure_airport, f.arrival_airport, f.status, f.aircraft_code, f.actual_departure, f.actual_arrival, f.update_ts
              Buffers: shared read=8624
              Worker 0:  actual time=0.015..17.275 rows=226669 loops=1
                Buffers: shared read=2881
              Worker 1:  actual time=0.015..17.139 rows=226331 loops=1
                Buffers: shared read=2840
        ->  Index Only Scan using booking_leg__flight_id on postgres_air.booking_leg  (cost=0.44..1.98 rows=83 width=4) (actual time=0.001..0.001 rows=1 loops=683178)
              Output: booking_leg.flight_id
              Index Cond: (booking_leg.flight_id = f.flight_id)
              Heap Fetches: 0
              Buffers: shared hit=2131358 read=4816
              Worker 0:  actual time=0.001..0.001 rows=1 loops=226669
                Buffers: shared hit=708246 read=1206
              Worker 1:  actual time=0.001..0.001 rows=1 loops=226331
                Buffers: shared hit=706604 read=1259
Planning:
  Buffers: shared hit=8 read=4
Planning Time: 0.180 ms
JIT:
  Functions: 12
  Options: Inlining false, Optimization false, Expressions true, Deforming true
  Timing: Generation 0.895 ms, Inlining 0.000 ms, Optimization 0.550 ms, Emission 9.143 ms, Total 10.588 ms
Execution Time: 409.962 ms
*/


/* Example 02 */
explain 
(analyze, verbose, buffers, costs)
SELECT * FROM flight WHERE flight_id IN
  (SELECT flight_id FROM booking_leg);

/*
Gather  (cost=1000.44..167432.76 rows=216673 width=71) (actual time=3.009..403.492 rows=508844 loops=1)
  Output: flight.flight_id, flight.flight_no, flight.scheduled_departure, flight.scheduled_arrival, flight.departure_airport, flight.arrival_airport, flight.status, flight.aircraft_code, flight.actual_departure, flight.actual_arrival, flight.update_ts
  Workers Planned: 02

  Workers Launched: 2
  Buffers: shared hit=2132249 read=12563
  ->  Nested Loop Semi Join  (cost=0.44..144765.46 rows=90280 width=71) (actual time=3.320..363.736 rows=169615 loops=3)
        Output: flight.flight_id, flight.flight_no, flight.scheduled_departure, flight.scheduled_arrival, flight.departure_airport, flight.arrival_airport, flight.status, flight.aircraft_code, flight.actual_departure, flight.actual_arrival, flight.update_ts
        Buffers: shared hit=2132249 read=12563
        Worker 0:  actual time=3.579..363.244 rows=160897 loops=1
          JIT:
            Functions: 4
            Options: Inlining false, Optimization false, Expressions true, Deforming true
            Timing: Generation 0.318 ms, Inlining 0.000 ms, Optimization 0.184 ms, Emission 3.325 ms, Total 3.828 ms
          Buffers: shared hit=687276 read=3933
        Worker 1:  actual time=3.563..362.004 rows=176520 loops=1
          JIT:
            Functions: 4
            Options: Inlining false, Optimization false, Expressions true, Deforming true
            Timing: Generation 0.289 ms, Inlining 0.000 ms, Optimization 0.184 ms, Emission 3.330 ms, Total 3.803 ms
          Buffers: shared hit=737697 read=4392
        ->  Parallel Seq Scan on postgres_air.flight  (cost=0.00..11470.58 rows=284658 width=71) (actual time=0.016..18.237 rows=227726 loops=3)
              Output: flight.flight_id, flight.flight_no, flight.scheduled_departure, flight.scheduled_arrival, flight.departure_airport, flight.arrival_airport, flight.status, flight.aircraft_code, flight.actual_departure, flight.actual_arrival, flight.update_ts
              Buffers: shared read=8624
              Worker 0:  actual time=0.017..17.344 rows=220482 loops=1
                Buffers: shared read=2781
              Worker 1:  actual time=0.017..18.401 rows=236264 loops=1
                Buffers: shared read=2984
        ->  Index Only Scan using booking_leg__flight_id on postgres_air.booking_leg  (cost=0.44..1.98 rows=83 width=4) (actual time=0.001..0.001 rows=1 loops=683178)
              Output: booking_leg.flight_id
              Index Cond: (booking_leg.flight_id = flight.flight_id)
              Heap Fetches: 0
              Buffers: shared hit=2132249 read=3939
              Worker 0:  actual time=0.001..0.001 rows=1 loops=220482
                Buffers: shared hit=687276 read=1152
              Worker 1:  actual time=0.001..0.001 rows=1 loops=236264
                Buffers: shared hit=737697 read=1408
Planning:
  Buffers: shared hit=8 read=4
Planning Time: 0.316 ms
JIT:
  Functions: 12
  Options: Inlining false, Optimization false, Expressions true, Deforming true
  Timing: Generation 0.841 ms, Inlining 0.000 ms, Optimization 0.561 ms, Emission 9.249 ms, Total 10.652 ms
Execution Time: 420.450 ms
*/
