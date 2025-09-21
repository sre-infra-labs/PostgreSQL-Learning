show search_path;

/* Temporary Tables
** With temporary tables, by default we don't get any statistics unless we run ANALYZE on temp table.
** Aggresive use of temporary tables can result in large queries being cancelled.
**
**
** CTE - Common Table Expressions
** Behaviour change in 12 or above
** join_collapse_limit. is not involved in CTE tables
** Postgres 12+. For SELECT statements with no recursion, if a CTE is used in a query only once, 
**   it will be inlined into the outer query (removing the optimizatin fence). If it is called more than once,
**   the old behaviour will be preserved.
** 
** Above CTE default behaviour can be overwritten by using keywords MATERIALIZED and NOT MATERIALIZED.
*/


-- Listing 7-3. Usage of the MATERIALIZED keyword
EXPLAIN
(ANALYZE, BUFFERS, COSTS,VERBOSE )
WITH flights_totals AS MATERIALIZED 
(
	SELECT bl.flight_id
		,departure_airport
		,(avg(price))::NUMERIC(7, 2) AS avg_price
		,count(DISTINCT passenger_id) AS num_passengers
	FROM booking b
	JOIN booking_leg bl USING (booking_id)
	JOIN flight f USING (flight_id)
	JOIN passenger p USING (booking_id)
	GROUP BY 1,2
)
SELECT flight_id
	,avg_price
	,num_passengers
FROM flights_totals
WHERE departure_airport = 'ORD';

