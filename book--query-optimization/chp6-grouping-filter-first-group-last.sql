

/* Listing 6-14: Average ticket price and total number of passengers per flight */
SELECT bl.flight_id,
       departure_airport,
       (avg(price))::numeric (7,2) AS avg_price,
       count(DISTINCT passenger_id) AS num_passengers
FROM booking b
JOIN booking_leg bl USING (booking_id)
JOIN flight f USING (flight_id)
JOIN passenger p USING (booking_id)
GROUP BY 1,2;



/* Listing 6-15: Average ticket price and total number of passengers on a specific flight
** Anti-pattern - Filter is applied after grouping
**
*/
EXPLAIN
(ANALYZE, BUFFERS, costs, VERBOSE)
WITH t_group_by AS (
    SELECT bl.flight_id,
            departure_airport,
            (avg(price))::numeric (7,2) AS avg_price,
            count(DISTINCT passenger_id) AS num_passengers
    FROM booking b
    JOIN booking_leg bl USING (booking_id)
    JOIN flight f USING (flight_id)
    JOIN passenger p USING (booking_id)
    GROUP BY 1,2
)
SELECT * 
FROM t_group_by
WHERE flight_id=222183;



/* Listing 6-15: Average ticket price and total number of passengers on a specific flight
** Correct Method - Filter is applied before grouping
**
*/
EXPLAIN
(ANALYZE, BUFFERS, costs, VERBOSE)
SELECT bl.flight_id,
       departure_airport,
       (avg(price))::numeric (7,2) AS avg_price,
       count(DISTINCT passenger_id) AS num_passengers
FROM booking b
JOIN booking_leg bl USING (booking_id)
JOIN flight f USING (flight_id)
JOIN passenger p USING (booking_id)
WHERE flight_id=222183
GROUP BY 1,2;


/* Listing 6-18: Condition can't be pushed inside the group
** Execution time 17 s
**
*/
EXPLAIN
(ANALYZE, BUFFERS, costs, VERBOSE)
SELECT  a.flight_id,
        a.avg_price,
        a.num_passengers
FROM (  SELECT bl.flight_id,
            departure_airport,
            (avg(price))::numeric (7,2) AS avg_price,
            count(DISTINCT passenger_id) AS num_passengers
        FROM booking b
        JOIN booking_leg bl USING (booking_id)
        JOIN flight f USING (flight_id)
        JOIN passenger p USING (booking_id)
        GROUP BY 1,2  
    ) a
WHERE flight_id in (SELECT flight_id FROM flight WHERE scheduled_departure BETWEEN '07-03-2023' AND '07-05-2023');


/* Listing 6-18: Condition placed in inner query to optimize
** Execution time 24 ms
**
*/
EXPLAIN
(ANALYZE, BUFFERS, costs, VERBOSE)
SELECT  a.flight_id,
        a.avg_price,
        a.num_passengers
FROM (  SELECT bl.flight_id,
            departure_airport,
            (avg(price))::numeric (7,2) AS avg_price,
            count(DISTINCT passenger_id) AS num_passengers
        FROM booking b
        JOIN booking_leg bl USING (booking_id)
        JOIN flight f USING (flight_id)
        JOIN passenger p USING (booking_id)
        WHERE f.scheduled_departure BETWEEN '07-03-2023' AND '07-05-2023'
        GROUP BY 1,2  
    ) a
;
