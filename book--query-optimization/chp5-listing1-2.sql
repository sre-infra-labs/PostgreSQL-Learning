/*  SHORT QUERY 
    A query is short when the number of rows needed to compute its output is small, no matter how large the involved tables are.
    Short query may read every row from small table but read only a small percentage of rows from large table.

*/

set search_path to postgres_air;

-- listing 5-1
SELECT d.airport_code AS departure_airport,
       a.airport_code AS arrival_airport
FROM  airport a,
      airport d;


-- listing 5-2
SELECT f.flight_no,
       f.scheduled_departure,
           boarding_time,
           p.last_name,
           p.first_name,
           bp.update_ts as pass_issued,
           ff.level
  FROM flight f
    JOIN booking_leg bl ON bl.flight_id = f.flight_id
    JOIN passenger p ON p.booking_id=bl.booking_id
      JOIN account a on a.account_id =p.account_id
      JOIN boarding_pass bp on bp.passenger_id=p.passenger_id
      LEFT OUTER JOIN frequent_flyer ff on ff.frequent_flyer_id=a.frequent_
flyer_id
      WHERE f.departure_airport = 'JFK'
            AND f.arrival_airport = 'ORD'
            AND f.scheduled_departure BETWEEN
        '2020-08-05' AND '2020-08-07';


-- listing 5-3
SELECT  avg(flight_length),
        avg (passengers)
FROM (  SELECT flight_no,
                scheduled_arrival -scheduled_departure AS flight_length,
                count(passenger_id) passengers
        FROM flight f
            JOIN booking_leg bl ON bl.flight_id = f.flight_id
            JOIN passenger p ON p.booking_id=bl.booking_id
            GROUP BY 1,2
    ) a;


