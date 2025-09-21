/*  Foreign Key Without Index */
set search_path to postgres_air;

explain analyze
SELECT f.flight_no,
       f.scheduled_departure,
       model,
       count(passenger_id) passengers
  FROM flight f
       JOIN booking_leg bl ON bl.flight_id = f.flight_id
       JOIN passenger p ON p.booking_id=bl.booking_id
         JOIN aircraft ac ON ac.code=f.aircraft_code
WHERE f.departure_airport ='JFK'
   AND f.scheduled_departure BETWEEN
       '2023-07-14' AND '2023-07-16'
GROUP BY 1,2,3;

alter table flight add constraint fk_flight__aircraft_code foreign key (aircraft_code) REFERENCES aircraft (code);


/*
Finalize GroupAggregate  (cost=269472.79..269690.28 rows=1548 width=52) (actual time=1109.790..1117.201 rows=127 loops=1)
  Group Key: f.flight_no, f.scheduled_departure, ac.model
  ->  Gather Merge  (cost=269472.79..269660.02 rows=1478 width=52) (actual time=1109.754..1117.101 rows=379 loops=1)
        Workers Planned: 2
        Workers Launched: 2
        ->  Partial GroupAggregate  (cost=268472.77..268489.40 rows=739 width=52) (actual time=1066.005..1067.878 rows=126 loops=3)
              Group Key: f.flight_no, f.scheduled_departure, ac.model
              ->  Sort  (cost=268472.77..268474.62 rows=739 width=48) (actual time=1065.987..1066.353 rows=8505 loops=3)
                    Sort Key: f.flight_no, f.scheduled_departure, ac.model
                    Sort Method: quicksort  Memory: 624kB
                    Worker 0:  Sort Method: quicksort  Memory: 1082kB
                    Worker 1:  Sort Method: quicksort  Memory: 573kB
                    ->  Hash Join  (cost=3251.87..268437.56 rows=739 width=48) (actual time=9.642..1057.122 rows=8505 loops=3)
                          Hash Cond: (p.booking_id = bl.booking_id)
                          ->  Parallel Seq Scan on passenger p  (cost=0.00..239689.66 rows=6796966 width=8) (actual time=0.147..612.715 rows=5437898 loops=3)
                          ->  Hash  (cost=3249.33..3249.33 rows=203 width=48) (actual time=7.186..7.191 rows=8873 loops=3)
                                Buckets: 16384 (originally 1024)  Batches: 1 (originally 1)  Memory Usage: 699kB
                                ->  Nested Loop  (cost=246.23..3249.33 rows=203 width=48) (actual time=1.521..5.992 rows=8873 loops=3)
                                      ->  Hash Join  (cost=241.15..712.45 rows=8 width=48) (actual time=1.482..1.706 rows=127 loops=3)
                                            Hash Cond: ((f.aircraft_code)::text = ac.code)
                                            ->  Bitmap Heap Scan on flight f  (cost=239.88..710.81 rows=129 width=20) (actual time=1.362..1.521 rows=127 loops=3)
                                                  Recheck Cond: ((scheduled_departure >= '2023-07-14 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2023-07-16 00:00:00+05:30'::timestamp with time zone) AND (departure_airport = 'JFK'::bpchar))
                                                  Heap Blocks: exact=88
                                                  ->  BitmapAnd  (cost=239.88..239.88 rows=129 width=0) (actual time=1.348..1.349 rows=0 loops=3)
                                                        ->  Bitmap Index Scan on flight_scheduled_departure  (cost=0.00..117.84 rows=8142 width=0) (actual time=0.346..0.346 rows=7962 loops=3)
                                                              Index Cond: ((scheduled_departure >= '2023-07-14 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2023-07-16 00:00:00+05:30'::timestamp with time zone))
                                                        ->  Bitmap Index Scan on flight_departure_airport  (cost=0.00..121.72 rows=10840 width=0) (actual time=0.906..0.906 rows=10530 loops=3)
                                                              Index Cond: (departure_airport = 'JFK'::bpchar)
                                            ->  Hash  (cost=1.12..1.12 rows=12 width=64) (actual time=0.095..0.096 rows=12 loops=3)
                                                  Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                                  ->  Seq Scan on aircraft ac  (cost=0.00..1.12 rows=12 width=64) (actual time=0.083..0.085 rows=12 loops=3)
                                      ->  Bitmap Heap Scan on booking_leg bl  (cost=5.07..316.29 rows=82 width=8) (actual time=0.007..0.026 rows=70 loops=381)
                                            Recheck Cond: (f.flight_id = flight_id)
                                            Heap Blocks: exact=1635
                                            ->  Bitmap Index Scan on booking_leg_flight_id  (cost=0.00..5.05 rows=82 width=0) (actual time=0.004..0.004 rows=70 loops=381)
                                                  Index Cond: (flight_id = f.flight_id)
Planning Time: 1.056 ms
Execution Time: 1117.747 ms
*/

/*
Finalize GroupAggregate  (cost=269472.79..269690.28 rows=1548 width=52) (actual time=2455.943..2466.310 rows=127 loops=1)
  Group Key: f.flight_no, f.scheduled_departure, ac.model
  ->  Gather Merge  (cost=269472.79..269660.02 rows=1478 width=52) (actual time=2455.899..2466.089 rows=377 loops=1)
        Workers Planned: 2
        Workers Launched: 2
        ->  Partial GroupAggregate  (cost=268472.77..268489.40 rows=739 width=52) (actual time=2400.371..2403.846 rows=126 loops=3)
              Group Key: f.flight_no, f.scheduled_departure, ac.model
              ->  Sort  (cost=268472.77..268474.62 rows=739 width=48) (actual time=2400.337..2400.986 rows=8505 loops=3)
                    Sort Key: f.flight_no, f.scheduled_departure, ac.model
                    Sort Method: quicksort  Memory: 905kB
                    Worker 0:  Sort Method: quicksort  Memory: 888kB
                    Worker 1:  Sort Method: quicksort  Memory: 677kB
                    ->  Hash Join  (cost=3251.87..268437.56 rows=739 width=48) (actual time=20.253..2382.053 rows=8505 loops=3)
                          Hash Cond: (p.booking_id = bl.booking_id)
                          ->  Parallel Seq Scan on passenger p  (cost=0.00..239689.66 rows=6796966 width=8) (actual time=0.346..1408.719 rows=5437898 loops=3)
                          ->  Hash  (cost=3249.33..3249.33 rows=203 width=48) (actual time=14.169..14.175 rows=8873 loops=3)
                                Buckets: 16384 (originally 1024)  Batches: 1 (originally 1)  Memory Usage: 699kB
                                ->  Nested Loop  (cost=246.23..3249.33 rows=203 width=48) (actual time=1.729..12.198 rows=8873 loops=3)
                                      ->  Hash Join  (cost=241.15..712.45 rows=8 width=48) (actual time=1.656..2.089 rows=127 loops=3)
                                            Hash Cond: ((f.aircraft_code)::text = ac.code)
                                            ->  Bitmap Heap Scan on flight f  (cost=239.88..710.81 rows=129 width=20) (actual time=1.483..1.752 rows=127 loops=3)
                                                  Recheck Cond: ((scheduled_departure >= '2023-07-14 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2023-07-16 00:00:00+05:30'::timestamp with time zone) AND (departure_airport = 'JFK'::bpchar))
                                                  Heap Blocks: exact=88
                                                  ->  BitmapAnd  (cost=239.88..239.88 rows=129 width=0) (actual time=1.468..1.469 rows=0 loops=3)
                                                        ->  Bitmap Index Scan on flight_scheduled_departure  (cost=0.00..117.84 rows=8142 width=0) (actual time=0.376..0.376 rows=7962 loops=3)
                                                              Index Cond: ((scheduled_departure >= '2023-07-14 00:00:00+05:30'::timestamp with time zone) AND (scheduled_departure <= '2023-07-16 00:00:00+05:30'::timestamp with time zone))
                                                        ->  Bitmap Index Scan on flight_departure_airport  (cost=0.00..121.72 rows=10840 width=0) (actual time=0.988..0.988 rows=10530 loops=3)
                                                              Index Cond: (departure_airport = 'JFK'::bpchar)
                                            ->  Hash  (cost=1.12..1.12 rows=12 width=64) (actual time=0.147..0.148 rows=12 loops=3)
                                                  Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                                  ->  Seq Scan on aircraft ac  (cost=0.00..1.12 rows=12 width=64) (actual time=0.128..0.136 rows=12 loops=3)
                                      ->  Bitmap Heap Scan on booking_leg bl  (cost=5.07..316.29 rows=82 width=8) (actual time=0.014..0.066 rows=70 loops=381)
                                            Recheck Cond: (f.flight_id = flight_id)
                                            Heap Blocks: exact=1635
                                            ->  Bitmap Index Scan on booking_leg_flight_id  (cost=0.00..5.05 rows=82 width=0) (actual time=0.009..0.009 rows=70 loops=381)
                                                  Index Cond: (flight_id = f.flight_id)
Planning Time: 2.832 ms
Execution Time: 2467.625 ms
*/