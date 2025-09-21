/* Listing 6-20: Calculating number of passengers per city per month
** 
** 
*/
EXPLAIN
(ANALYZE, costs, verbose, BUFFERS)
SELECT  city,
        date_trunc('month', scheduled_departure) AS month,
        count(*)  passengers
FROM airport  a
JOIN flight f ON airport_code = departure_airport
JOIN booking_leg l ON f.flight_id =l.flight_id
JOIN boarding_pass b ON b.booking_leg_id = l.booking_leg_id
GROUP BY 1,2
ORDER BY 3 DESC;


EXPLAIN
(ANALYZE, costs, verbose, BUFFERS)
SELECT  city,
        date_trunc('month', scheduled_departure) AS month,
        count(*)  passengers
FROM airport  a
JOIN flight f ON airport_code = departure_airport
JOIN booking_leg l ON f.flight_id =l.flight_id
JOIN boarding_pass b ON b.booking_leg_id = l.booking_leg_id
GROUP BY 1,2
ORDER BY 3 DESC;


/* Performance improvement by pushing the GROUP BY inside */
SELECT  city,
        date_trunc('month', scheduled_departure),
        sum(passengers)  passengers
FROM airport  a
JOIN flight f ON airport_code = departure_airport
JOIN (
      SELECT flight_id, count(*) passengers
      FROM booking_leg l
      JOIN boarding_pass b USING (booking_leg_id)
      GROUP BY flight_id
) cnt
USING (flight_id)
GROUP BY 1,2
ORDER BY 3 DESC;

