set search_path to postgres_air;

explain analyze
SELECT * FROM flight
WHERE 1=1
and departure_airport='LAX' -- 36 rows affected
--and departure_airport='FUK' -- 1 row affected
AND update_ts BETWEEN '2023-07-16' AND '2023-07-18'
AND status='Delayed'
AND scheduled_departure BETWEEN '2023-07-16' AND '2023-07-18'
--ORDER BY scheduled_departure;

/*  Plan for departure_airport='LAX'

Bitmap Heap Scan on flight  (cost=386.95..394.91 rows=1 width=71) (actual time=2.247..2.306 rows=36 loops=1)
  Recheck Cond: ((scheduled_departure >= '2023-07-16 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2023-07-18 00:00:00+05:30'::timestamp with time zone) AND (departure_airport = 'LAX'::bpchar) AND (update_ts >= '2023-07-16 00:00:00+05:30'::timestamp with time zone) AND (update_ts <= '2023-07-18 00:00:00+05:30'::timestamp with time zone))
  Filter: (status = 'Delayed'::text)
  Heap Blocks: exact=22
  ->  BitmapAnd  (cost=386.95..386.95 rows=2 width=0) (actual time=2.230..2.232 rows=0 loops=1)
        ->  Bitmap Index Scan on flight_scheduled_departure  (cost=0.00..102.25 rows=6982 width=0) (actual time=0.363..0.364 rows=6953 loops=1)
              Index Cond: ((scheduled_departure >= '2023-07-16 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2023-07-18 00:00:00+05:30'::timestamp with time zone))
        ->  Bitmap Index Scan on flight_departure_airport  (cost=0.00..138.36 rows=12525 width=0) (actual time=1.094..1.094 rows=11804 loops=1)
              Index Cond: (departure_airport = 'LAX'::bpchar)
        ->  Bitmap Index Scan on flight_update_ts  (cost=0.00..145.85 rows=9342 width=0) (actual time=0.612..0.612 rows=9096 loops=1)
              Index Cond: ((update_ts >= '2023-07-16 00:00:00+05:30'::timestamp with time zone) AND (update_ts <= '2023-07-18 00:00:00+05:30'::timestamp with time zone))
Planning Time: 0.244 ms
Execution Time: 2.409 ms
*/

/*  Plan for departure_airport='FUK'

Bitmap Heap Scan on flight  (cost=109.83..125.67 rows=1 width=71) (actual time=0.263..0.269 rows=1 loops=1)
  Recheck Cond: ((departure_airport = 'FUK'::bpchar) AND (scheduled_departure >= '2023-07-16 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2023-07-18 00:00:00+05:30'::timestamp with time zone))
  Filter: ((update_ts >= '2023-07-16 00:00:00+05:30'::timestamp with time zone) AND (update_ts <= '2023-07-18 00:00:00+05:30'::timestamp with time zone) AND (status = 'Delayed'::text))
  Rows Removed by Filter: 4
  Heap Blocks: exact=4
  ->  BitmapAnd  (cost=109.83..109.83 rows=4 width=0) (actual time=0.255..0.255 rows=0 loops=1)
        ->  Bitmap Index Scan on flight_departure_airport  (cost=0.00..7.33 rows=388 width=0) (actual time=0.061..0.061 rows=468 loops=1)
              Index Cond: (departure_airport = 'FUK'::bpchar)
        ->  Bitmap Index Scan on flight_scheduled_departure  (cost=0.00..102.25 rows=6982 width=0) (actual time=0.178..0.178 rows=6953 loops=1)
              Index Cond: ((scheduled_departure >= '2023-07-16 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2023-07-18 00:00:00+05:30'::timestamp with time zone))
Planning Time: 0.153 ms
Execution Time: 0.299 ms
*/