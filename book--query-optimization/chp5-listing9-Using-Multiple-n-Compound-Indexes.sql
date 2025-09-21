set search_path to postgres_air;

EXPLAIN ANALYZE
SELECT scheduled_departure
       ,scheduled_arrival
FROM flight
WHERE departure_airport='ORD' AND arrival_airport='JFK'
AND scheduled_departure BETWEEN '2023-06-05' AND '2023-07-26';
--group by scheduled_departure::DATE
--order by counts desc
/*
Indexes:
    "flight_pkey" PRIMARY KEY, btree (flight_id)
    "flight_actual_departure" btree (actual_departure)
    "flight_arrival_airport" btree (arrival_airport)
    "flight_departure_airport" btree (departure_airport)
    "flight_scheduled_departure" btree (scheduled_departure)
    "flight_update_ts" btree (update_ts)


Bitmap Heap Scan on flight  (cost=269.49..1002.13 rows=58 width=16) (actual time=1.946..2.105 rows=51 loops=1)
  Recheck Cond: ((arrival_airport = 'JFK'::bpchar) AND (departure_airport = 'ORD'::bpchar))
  Filter: ((scheduled_departure >= '2023-06-05 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2023-07-26 00:00:00+05:30'::timestamp with time zone))
  Rows Removed by Filter: 131
  Heap Blocks: exact=154
  ->  BitmapAnd  (cost=269.49..269.49 rows=208 width=0) (actual time=1.890..1.891 rows=0 loops=1)
        ->  Bitmap Index Scan on flight_arrival_airport  (cost=0.00..118.48 rows=10407 width=0) (actual time=0.853..0.853 rows=10530 loops=1)
              Index Cond: (arrival_airport = 'JFK'::bpchar)
        ->  Bitmap Index Scan on flight_departure_airport  (cost=0.00..150.73 rows=13641 width=0) (actual time=0.740..0.740 rows=12922 loops=1)
              Index Cond: (departure_airport = 'ORD'::bpchar)
Planning Time: 0.172 ms
Execution Time: 2.222 ms
*/


explain analyze
SELECT scheduled_departure ,
       scheduled_arrival
FROM flight
WHERE departure_airport='ORD' AND arrival_airport='JFK'
AND scheduled_arrival BETWEEN '2020-07-03' AND '2020-07-04';

/*
Indexes:
    "flight_pkey" PRIMARY KEY, btree (flight_id)
    "flight_actual_departure" btree (actual_departure)
    "flight_arrival_airport" btree (arrival_airport)
    "flight_departure_airport" btree (departure_airport)
    "flight_scheduled_departure" btree (scheduled_departure)
    "flight_update_ts" btree (update_ts)


Bitmap Heap Scan on flight  (cost=269.46..1002.11 rows=1 width=16) (actual time=1.881..1.882 rows=0 loops=1)
  Recheck Cond: ((arrival_airport = 'JFK'::bpchar) AND (departure_airport = 'ORD'::bpchar))
  Filter: ((scheduled_arrival >= '2020-07-03 00:00:00+05:30'::timestamp with time zone) AND (scheduled_arrival <= '2020-07-04 00:00:00+05:30'::timestamp with time zone))
  Rows Removed by Filter: 182
  Heap Blocks: exact=154
  ->  BitmapAnd  (cost=269.46..269.46 rows=208 width=0) (actual time=1.425..1.426 rows=0 loops=1)
        ->  Bitmap Index Scan on flight_arrival_airport  (cost=0.00..118.48 rows=10407 width=0) (actual time=0.645..0.646 rows=10530 loops=1)
              Index Cond: (arrival_airport = 'JFK'::bpchar)
        ->  Bitmap Index Scan on flight_departure_airport  (cost=0.00..150.73 rows=13641 width=0) (actual time=0.552..0.552 rows=12922 loops=1)
              Index Cond: (departure_airport = 'ORD'::bpchar)
Planning Time: 1.446 ms
Execution Time: 2.010 ms
*/


-- create compound index
CREATE INDEX flight_depart_arr_sched_dep ON flight(departure_airport, arrival_airport, scheduled_departure);


explain analyze
SELECT scheduled_departure ,
       scheduled_arrival
FROM flight
WHERE departure_airport='ORD' AND arrival_airport='JFK'
AND scheduled_arrival BETWEEN '2020-07-03' AND '2020-07-04';

/*
Indexes:
    "flight_pkey" PRIMARY KEY, btree (flight_id)
    "flight_actual_departure" btree (actual_departure)
    "flight_arrival_airport" btree (arrival_airport)
    "flight_depart_arr_sched_dep" btree (departure_airport, arrival_airport, scheduled_departure)
    "flight_departure_airport" btree (departure_airport)
    "flight_scheduled_departure" btree (scheduled_departure)
    "flight_update_ts" btree (update_ts)


Bitmap Heap Scan on flight  (cost=6.51..739.15 rows=1 width=16) (actual time=0.227..0.227 rows=0 loops=1)
  Recheck Cond: ((departure_airport = 'ORD'::bpchar) AND (arrival_airport = 'JFK'::bpchar))
  Filter: ((scheduled_arrival >= '2020-07-03 00:00:00+05:30'::timestamp with time zone) AND (scheduled_arrival <= '2020-07-04 00:00:00+05:30'::timestamp with time zone))
  Rows Removed by Filter: 182
  Heap Blocks: exact=154
  ->  Bitmap Index Scan on flight_depart_arr_sched_dep  (cost=0.00..6.50 rows=208 width=0) (actual time=0.042..0.042 rows=182 loops=1)
        Index Cond: ((departure_airport = 'ORD'::bpchar) AND (arrival_airport = 'JFK'::bpchar))
Planning Time: 0.112 ms
Execution Time: 0.245 ms
*/