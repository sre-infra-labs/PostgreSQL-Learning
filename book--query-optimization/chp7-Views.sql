/* Views
** 
** 
*/
SHOW SEARCH_PATH;

/* VIEWS
**
** In practice, views are created precisely for the purpose of encapsulation.
**   But making complex usage of same leads to performance degradation.
**
** With constant search filter, in first step of query processing, the query parser
**  transforms views into inline subqueries. This way, in this query,
**  constant based filtering condition is pushed inside the grouping
**
** When to say no for views?
** Incase of transformation columns in view, its better to not have view.
** Incase of nonconstant filters in view usage, its better to replace view with code
** Avoid nested views
*/

-- Listing 7-4. Create view. Calculates the totals of all flights.
CREATE VIEW flight_stats AS
SELECT bl.flight_id,
       f.departure_airport,
      (avg(price))::numeric (7,2) AS avg_price,
       count(DISTINCT passenger_id) AS num_passengers
FROM booking b
      JOIN booking_leg bl USING (booking_id)
JOIN flight f USING (flight_id)
      JOIN passenger p USING (booking_id)
GROUP BY 1,2;

-- Listing 7-4. Execute view with constant filter
EXPLAIN
(ANALYZE, BUFFERS, VERBOSE, COSTS)
SELECT * FROM flight_stats
   WHERE flight_id=222183;


/* Listing 7-5. With nonconstant search criterion, filters are applied after processing the view.
** 
**
*/
EXPLAIN
(ANALYZE, BUFFERS, VERBOSE, COSTS)
SELECT * 
FROM flight_stats fs
JOIN (SELECT flight_id FROM flight f
      WHERE actual_departure between '2023-08-01' and '2023-08-16'
    ) fl
    ON fl.flight_id=fs.flight_id;


/* Listing 7-7. View with column transformation
**
*/
CREATE VIEW flight_departure as
SELECT bl.flight_id,
       departure_airport,
       coalesce(actual_departure, scheduled_departure)::date
       AS  departure_date,
       count(DISTINCT passenger_id) AS num_passengers
FROM booking b
JOIN booking_leg bl USING (booking_id)
JOIN flight f USING (flight_id)
JOIN passenger p USING (booking_id)
GROUP BY 1,2,3;

-- Listing 7-7
-- Filter on normal column with constant
EXPLAIN
(ANALYZE, BUFFERS, VERBOSE, COSTS)
SELECT flight_id,
       num_passengers
FROM flight_departure
WHERE flight_id = 22183;

-- Filter on transformation column with constant
EXPLAIN
(ANALYZE, BUFFERS, VERBOSE, COSTS)
SELECT flight_id,
       num_passengers
FROM flight_departure
WHERE departure_date = '2023-07-01';

-- Query on view just to get flights from a particular airport
    -- Unnecessary complex plan as the main view purpose is defeted
EXPLAIN
(ANALYZE, BUFFERS, VERBOSE, COSTS)
SELECT flight_id
FROM flight_departure
WHERE departure_airport='ORD';

-- Query on get flights from a particular airport
    -- More efficient compared to using view
SELECT flight_id FROM flight where departure_airport='ORD'
AND flight_id IN (SELECT flight_id FROM booking_leg);

