/* join_collapse_limit parameter (default 8)
** Disable Cost Based Optimization
** This parameter caps the number of tables in a join that will be still processed by cost-based optimizer.
** 
** This means that if the number of tables in a join is eight or fewer, the optimizer will perform a 
**   selection of candidate plans, compare plans, and choose the best one. But if the number of tables
**   is nine or more, it will simply execute the joins in the order the tables are listed in the SELECT statement.
*/


set join_collapse_limit = 1;

EXPLAIN
--(ANALYZE, COSTS, BUFFERS, VERBOSE)
SELECT departure_airport, booking_id, is_returning
FROM booking_leg bl
JOIN flight f USING (flight_id)
WHERE departure_airport IN (SELECT airport_code
                FROM airport WHERE iso_country='US')
    AND bl.booking_id IN (SELECT booking_id FROM booking
                        WHERE update_ts>'2020-08-01');


set join_collapse_limit = 8;

EXPLAIN
(ANALYZE, COSTS, BUFFERS, VERBOSE)
SELECT departure_airport, booking_id, is_returning
FROM booking_leg bl
JOIN flight f USING (flight_id)
WHERE departure_airport IN (SELECT airport_code
                FROM airport WHERE iso_country='US')
    AND bl.booking_id IN (SELECT booking_id FROM booking
                        WHERE update_ts>'2023-08-01');