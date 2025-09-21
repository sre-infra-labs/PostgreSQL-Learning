/* Materialized Views
**
** A materialized view is a database object that combines  both a query definition
**  and a table to store the results of the query at the time it is run.
** 
** A materialized view reflects the data at the time it was last refreshed, not current data.
** 
** It is different from a table as we can't modify data in a materialized view directly.
** In contrast to views, materialized view behave exactly like tables.
** Indexes can also be created on materialized views, although they cannot have primary & foreign keys
*/


-- Listing 7-9. Create a materialized view
CREATE MATERIALIZED VIEW flight_departure_mv
AS
SELECT bl.flight_id,
       departure_airport,
       coalesce(actual_departure,
                scheduled_departure)::date departure_date,
       count(DISTINCT passenger_id) AS num_passengers
FROM booking b
JOIN booking_leg bl USING (booking_id)
JOIN flight f USING (flight_id)
JOIN passenger p USING (booking_id)
GROUP BY 1,2,3;

/* Create indexes on Materialized View */

CREATE UNIQUE INDEX flight_departure_flight_id
ON flight_departure_mv(flight_id);
--
CREATE INDEX flight_departure_dep_date
ON flight_departure_mv(departure_date);
--
CREATE INDEX flight_departure_dep_airport
ON flight_departure_mv(departure_airport);

/* Executing select query on MV
** Should use index
*/
EXPLAIN
(ANALYZE, COSTS, BUFFERS, VERBOSE)
SELECT flight_id,
       num_passengers
FROM flight_departure_mv
WHERE departure_date = '2020-08-01';
/*
Index Scan using flight_departure_dep_date on postgres_air.flight_departure_mv  (cost=0.42..93.77 rows=2290 width=12) (actual time=0.020..0.020 rows=0 loops=1)
  Output: flight_id, num_passengers
  Index Cond: (flight_departure_mv.departure_date = '2020-08-01'::date)
  Buffers: shared read=3
Planning:
  Buffers: shared hit=46 read=3
Planning Time: 0.216 ms
Execution Time: 0.036 ms
*/


/* Refreshing Materialized Views 
**
** Materialized views cannot be updated incrementally.
** Also, refresh schedule can not be specified in view definition.
** By default, during refresh process, the materialized view is locked, and 
**   its content are unavailable to other processes.
*/
REFRESH MATERIALIZED VIEW flight_departure_mv;


/* IMP: To make the prior versin of a materialized view available during refresh,
**   the CONCURRENTLY keyword is added in REFRESH query.
**
** A materialized view can only be refreshed concurrently if it has a unique index.
** The concurrent refresh will take longer than regular refresh, but access to the
**   materialized view won't be blocked.
*/
REFRESH MATRIALIZED VIEW CONCURRENTLY flight_departure_mv;


/* Create a Materialized View or Not?

Since materialized view refreshes take time and selecting from a materialized view is going to
be much faster than from a view, consider the following:

• How often does the data in the base tables change?
• How critical is it to have the most recent data?
• How often do we need to select this data (or rather how many reads per one refresh are expected)?
• How many different queries will use this data?
*/



