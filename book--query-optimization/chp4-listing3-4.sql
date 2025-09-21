--set search_path to postgres_air;

-- listing 4-3
explain analyze
SELECT flight_id, scheduled_departure
   FROM flight f
   JOIN airport a
       ON departure_airport=airport_code
          AND iso_country='US';
    -- (338858 row(s) affected)
/*
Hash Join  (cost=20.41..17280.52 rows=139202 width=12) (actual time=0.461..166.056 rows=338858 loops=1)
  Hash Cond: (f.departure_airport = a.airport_code)
  ->  Seq Scan on flight f  (cost=0.00..15455.78 rows=683178 width=16) (actual time=0.191..57.169 rows=683178 loops=1)
  ->  Hash  (cost=18.65..18.65 rows=141 width=4) (actual time=0.257..0.259 rows=141 loops=1)
        Buckets: 1024  Batches: 1  Memory Usage: 13kB
        ->  Seq Scan on airport a  (cost=0.00..18.65 rows=141 width=4) (actual time=0.029..0.219 rows=141 loops=1)
              Filter: (iso_country = 'US'::text)
              Rows Removed by Filter: 551
Planning Time: 0.679 ms
Execution Time: 172.704 ms
*/

-- listing 4-4
explain analyze
SELECT flight_id, scheduled_departure
   FROM flight f
   JOIN airport a
ON departure_airport=airport_code
AND iso_country='CZ';
    -- (2912 row(s) affected)
/*
Nested Loop  (cost=12.63..3028.61 rows=987 width=12) (actual time=0.470..2.825 rows=2912 loops=1)
  ->  Seq Scan on airport a  (cost=0.00..18.65 rows=1 width=4) (actual time=0.081..0.170 rows=1 loops=1)
        Filter: (iso_country = 'CZ'::text)
        Rows Removed by Filter: 691
  ->  Bitmap Heap Scan on flight f  (cost=12.63..2999.37 rows=1059 width=16) (actual time=0.381..2.206 rows=2912 loops=1)
        Recheck Cond: (departure_airport = a.airport_code)
        Heap Blocks: exact=831
        ->  Bitmap Index Scan on flight_departure_airport  (cost=0.00..12.37 rows=1059 width=0) (actual time=0.262..0.262 rows=2912 loops=1)
              Index Cond: (departure_airport = a.airport_code)
Planning Time: 0.579 ms
Execution Time: 2.966 ms
*/

