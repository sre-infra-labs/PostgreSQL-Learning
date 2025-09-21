--SELECT inet_server_addr() AS server_ip, inet_server_port() AS server_port;

set search_path to postgres_air;

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
WITH bk_chi AS (
WITH bk AS (
WITH level4 AS (SELECT * FROM account WHERE
frequent_flyer_id IN (
      SELECT frequent_flyer_id FROM frequent_flyer WHERE level =4
))
SELECT * FROM booking WHERE account_id IN
(SELECT account_id FROM level4
) )
SELECT * FROM bk WHERE bk.booking_id IN
   (SELECT booking_id FROM booking_leg WHERE
        Leg_num=1 AND is_returning IS false
        AND flight_id IN (
SELECT flight_id FROM flight
      WHERE
           departure_airport IN ('ORD', 'MDW')
           AND scheduled_departure:: DATE='2020-07-04')
))
SELECT count(*) from passenger WHERE booking_id IN (
      SELECT booking_id FROM bk_chi);


EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT count(*) FROM
booking bk
JOIN booking_leg bl ON bk.booking_id=bl.booking_id
JOIN flight f ON f.flight_id=bl.flight_id
JOIN account a ON a.account_id=bk.account_id
JOIN frequent_flyer ff ON ff.frequent_flyer_id=a.frequent_flyer_id
JOIN passenger ps ON ps.booking_id=bk.booking_id
WHERE level=4
AND leg_num=1
AND is_returning IS false
AND departure_airport IN ('ORD', 'MDW')
AND scheduled_departure BETWEEN '2020-07-04'
AND '2020-07-05';