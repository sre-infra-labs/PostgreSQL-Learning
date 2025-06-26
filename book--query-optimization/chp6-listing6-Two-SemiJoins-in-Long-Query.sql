show search_path;
select current_user;

create index booking__update_ts on booking (update_ts);


/* Listing 6-6
** Two semi-joins in one long query
** Find bookings of flights departing from United States, but is limited to booking updated since July 1, 2023
**
** 1) Optimizer chooses Hash Join over Semi Join because 
*/
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
--explain
SELECT departure_airport, booking_id, is_returning
FROM booking_leg bl
JOIN flight f USING (flight_id)
WHERE 1=1
AND departure_airport IN (SELECT airport_code FROM airport WHERE iso_country='US')
AND bl.booking_id IN (SELECT booking_id FROM booking WHERE update_ts>'2023-07-01');

SELECT airport_code FROM airport WHERE iso_country='US'; -- (141 row(s) affected)
select count(*) from flight -- 683,178
SELECT booking_id FROM booking WHERE update_ts>'2023-07-01'; -- (1,858,073 row(s) affected)
/*
Gather  (cost=131604.20..492719.79 rows=1191541 width=9)
  Workers Planned: 2
  ->  Parallel Hash Join  (cost=130604.20..372565.69 rows=496475 width=9)
        Hash Cond: (bl.booking_id = booking.booking_id)
        ->  Nested Loop  (cost=20.85..220156.59 rows=1519143 width=9)
              ->  Hash Join  (cost=20.41..12242.79 rows=58001 width=8)
                    Hash Cond: (f.departure_airport = airport.airport_code)
                    ->  Parallel Seq Scan on flight f  (cost=0.00..11470.58 rows=284658 width=8)
                    ->  Hash  (cost=18.65..18.65 rows=141 width=4)
                          ->  Seq Scan on airport  (cost=0.00..18.65 rows=141 width=4)
                                Filter: (iso_country = 'US'::text)
              ->  Index Scan using booking_leg__flight_id on booking_leg bl  (cost=0.44..2.75 rows=83 width=9)
                    Index Cond: (flight_id = f.flight_id)
        ->  Parallel Hash  (cost=117975.75..117975.75 rows=768448 width=8)
              ->  Parallel Seq Scan on booking  (cost=0.00..117975.75 rows=768448 width=8)
                    Filter: (update_ts > '2023-07-01 00:00:00+05:30'::timestamp with time zone)
JIT:
  Functions: 25
  Options: Inlining false, Optimization false, Expressions true, Deforming true
*/




EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
--explain
SELECT departure_airport, booking_id, is_returning
FROM booking_leg bl
JOIN flight f USING (flight_id)
WHERE 1=1
AND departure_airport IN (SELECT airport_code FROM airport WHERE iso_country='US')
AND bl.booking_id IN (SELECT booking_id FROM booking WHERE update_ts>'2023-08-01');

--SELECT airport_code FROM airport WHERE iso_country='US'; -- (141 row(s) affected)
--select count(*) from flight; -- 683,178
--SELECT booking_id FROM booking WHERE update_ts>'2023-08-01'; -- (471,393 row(s) affected)


EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
--explain
SELECT departure_airport, booking_id, is_returning
FROM booking_leg bl
JOIN flight f USING (flight_id)
WHERE 1=1
AND departure_airport IN (SELECT airport_code FROM airport WHERE iso_country='US')
AND bl.booking_id IN (SELECT booking_id FROM booking WHERE coalesce(update_ts,'2023-08-03') > '2023-08-02');


EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
--explain
SELECT departure_airport, booking_id, is_returning
FROM booking_leg bl
JOIN flight f USING (flight_id)
WHERE 1=1
AND departure_airport IN (SELECT airport_code FROM airport WHERE iso_country='US')
AND bl.booking_id IN (SELECT booking_id FROM booking WHERE update_ts > '2023-08-10');