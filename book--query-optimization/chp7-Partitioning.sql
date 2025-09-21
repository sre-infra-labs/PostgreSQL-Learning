/* Partitioning
** 
**
A partitioned table consists of several partitions, each of which is defined as a table. 
Each table row is stored in one of the partitions according to rules specified when the partitioned table is created.
** 
The most common case is range partitioning, meaning that each partition contains
rows that have values of an attribute in the range assigned to the partition. Ranges
assigned to different partitions cannot intersect, and a row that does not fit into any
partition cannot be inserted.
**
** Partitioning may be used to distribute large amounts of data across several database servers: a partition can be a foreign table.
**
** From a performance perspective, partitioning may reduce the time needed for full
table scans: if a query contains conditions on the partitioning key, the scan is limited to
these partitions only
**
** Partitions may have their own indexes that obviously are smaller than an index on
the whole partitioned table.
*/

---create table
---
CREATE TABLE boarding_pass_part 
(
    boarding_pass_id SERIAL,
    passenger_id BIGINT NOT NULL,
    booking_leg_id BIGINT NOT NULL,
    seat TEXT,
    boarding_time TIMESTAMPTZ,
    precheck BOOLEAN NOT NULL,
    update_ts TIMESTAMPTZ
)
PARTITION BY RANGE (boarding_time);

--create partitions
--
CREATE TABLE boarding_pass_may PARTITION OF boarding_pass_part
FOR VALUES
    FROM ('2023-05-01'::timestamptz)
    TO ('2023-06-01'::timestamptz) ;
--
CREATE TABLE boarding_pass_june PARTITION OF boarding_pass_part
FOR VALUES
    FROM ('2023-06-01'::timestamptz)
    TO ('2023-07-01'::timestamptz);
--
CREATE TABLE boarding_pass_july PARTITION OF boarding_pass_part
FOR VALUES
    FROM ('2023-07-01'::timestamptz)
    TO ('2023-08-01'::timestamptz);
--
CREATE TABLE boarding_pass_aug PARTITION OF boarding_pass_part
FOR VALUES
    FROM ('2023-08-01'::timestamptz)
    TO ('2023-09-01'::timestamptz);
--
INSERT INTO boarding_pass_part SELECT * from boarding_pass;


EXPLAIN
(ANALYZE, BUFFERS, VERBOSE, COSTS)
SELECT  city,
        date_trunc('month', scheduled_departure),
        sum(passengers)  passengers
FROM airport  a
JOIN flight f ON airport_code = departure_airport
JOIN (
    SELECT flight_id, count(*) passengers
    FROM   booking_leg l
    JOIN boarding_pass b USING (booking_leg_id)
        WHERE boarding_time > '2023-07-15'
        and boarding_time <'2023-07-31'
    GROUP BY flight_id
) cnt
USING (flight_id)
GROUP BY 1,2
ORDER BY 3 DESC;


EXPLAIN
(ANALYZE, BUFFERS, VERBOSE, COSTS)
SELECT  city,
        date_trunc('month', scheduled_departure),
        sum(passengers)  passengers
FROM airport  a
JOIN flight f ON airport_code = departure_airport
JOIN (
    SELECT flight_id, count(*) passengers
    FROM   booking_leg l
    JOIN boarding_pass_part b USING (booking_leg_id)
        WHERE boarding_time > '2023-07-15'
        and boarding_time <'2023-07-31'
    GROUP BY flight_id
) cnt
USING (flight_id)
GROUP BY 1,2
ORDER BY 3 DESC;


EXPLAIN
(ANALYZE, BUFFERS, VERBOSE, COSTS)
SELECT  city,
        date_trunc('month', scheduled_departure),
        sum(passengers)  passengers
FROM airport  a
JOIN flight f ON airport_code = departure_airport
JOIN (
    SELECT flight_id, count(*) passengers
    FROM   booking_leg l
    JOIN boarding_pass_part b USING (booking_leg_id)
        WHERE boarding_time > '2023-07-15'
        and boarding_time <'2023-07-31'
    GROUP BY flight_id
) cnt
USING (flight_id)
GROUP BY 1,2
ORDER BY 3 DESC;
