/* Listing 5-15. SELECT with three different sets of parameters
** 
*/

set search_path to postgres_air;

-- create supporting indexes
create index passenger__lastname_lowercase on passenger (lower(last_name));
create index boarding_pass__passenger_id on boarding_pass(passenger_id);
create index boarding_pass__booking_leg_id on boarding_pass(booking_leg_id);
create index booking_leg__flight_id on booking_Leg(flight_id);

/* INDEX structure of 2 tables

postgres_air=# \d flight
                                            Table "postgres_air.flight"
       Column        |           Type           | Collation | Nullable |                  Default                  
---------------------+--------------------------+-----------+----------+-------------------------------------------
 flight_id           | integer                  |           | not null | nextval('flight_flight_id_seq'::regclass)
 flight_no           | text                     |           | not null | 
 scheduled_departure | timestamp with time zone |           | not null | 
 scheduled_arrival   | timestamp with time zone |           | not null | 
 departure_airport   | character(3)             |           | not null | 
 arrival_airport     | character(3)             |           | not null | 
 status              | text                     |           | not null | 
 aircraft_code       | character(3)             |           | not null | 
 actual_departure    | timestamp with time zone |           |          | 
 actual_arrival      | timestamp with time zone |           |          | 
 update_ts           | timestamp with time zone |           |          | 
Indexes:
    "flight_pkey" PRIMARY KEY, btree (flight_id)
    "flight_departure_airport" btree (departure_airport)
    "flight_scheduled_departure" btree (scheduled_departure)
    "flight_update_ts" btree (update_ts)


postgres_air=# \d passenger
                                          Table "postgres_air.passenger"
    Column    |           Type           | Collation | Nullable |                     Default                     
--------------+--------------------------+-----------+----------+-------------------------------------------------
 passenger_id | integer                  |           | not null | nextval('passenger_passenger_id_seq'::regclass)
 booking_id   | integer                  |           | not null | 
 booking_ref  | text                     |           |          | 
 passenger_no | integer                  |           |          | 
 first_name   | text                     |           | not null | 
 last_name    | text                     |           | not null | 
 account_id   | integer                  |           |          | 
 update_ts    | timestamp with time zone |           |          | 
 age          | integer                  |           |          | 
Indexes:
    "passenger_pkey" PRIMARY KEY, btree (passenger_id)
    "passenger__lastname_lowercase" btree (lower(last_name))


postgres_air=# \d boarding_pass
                                        Table "postgres_air.boarding_pass"
     Column     |           Type           | Collation | Nullable |                    Default                     
----------------+--------------------------+-----------+----------+------------------------------------------------
 pass_id        | integer                  |           | not null | nextval('boarding_pass_pass_id_seq'::regclass)
 passenger_id   | bigint                   |           |          | 
 booking_leg_id | bigint                   |           |          | 
 seat           | text                     |           |          | 
 boarding_time  | timestamp with time zone |           |          | 
 precheck       | boolean                  |           |          | 
 update_ts      | timestamp with time zone |           |          | 
Indexes:
    "boarding_pass_pkey" PRIMARY KEY, btree (pass_id)
    "boarding_pass__passenger_id" btree (passenger_id)
    "boarding_pass_update_ts" btree (update_ts)
*/



-- #1 - departure airport has high selectivity, and passenger name has low selectivity.
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT  p.last_name,
        p.first_name
FROM passenger p
JOIN boarding_pass bp USING (passenger_id)
JOIN booking_Leg bl USING (booking_leg_id)
JOIN flight USING(flight_id)
WHERE departure_airport='LAX'
AND lower(last_name)='clark';

/*

*/


-- #2 - both departure airport and passenger name have high selectivity
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT  p.last_name,
        p.first_name
FROM passenger p
JOIN boarding_pass bp USING (passenger_id)
JOIN booking_Leg bl USING (booking_leg_id)
JOIN flight USING(flight_id)
WHERE departure_airport='LAX'
AND lower(last_name)='smith';

/*

*/


-- #3 - departure airport has low selectivity, and passenger name has high selectivity
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT  p.last_name,
        p.first_name
FROM passenger p
JOIN boarding_pass bp USING (passenger_id)
JOIN booking_Leg bl USING (booking_leg_id)
JOIN flight USING(flight_id)
WHERE departure_airport='FUK'
AND lower(last_name)='smith';

/*

*/