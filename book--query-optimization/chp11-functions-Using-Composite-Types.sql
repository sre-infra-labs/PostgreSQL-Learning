show search_path;

/* Function Execution
** The PL/pgSQL interpreter parses the function's source text and produces an
(internal) instruction tree the first time the function is called within each session. Even
then, individual SQL expressions and commands used in the function are not translated
immediately. Only when the execution path reaches a specific command is it analyzed
and a prepared statement is created. It will be reused if the same function is executed
again in the same session. One of the implications of this is that if your function contains
some conditional code (i.e., IF THEN ELSE or CASE statements), you may not even
discover the syntax errors in your code, if this portion was not reached during execution.
** 
** Atomic Nature
We can’t initiate transactions inside PostgreSQL functions, so in the case of DML statements, 
it’s always “all or nothing.”
**
** Execution Plan for function execution
Second, the PostgreSQL optimizer knows nothing about function execution when it
optimizes an execution plan, which includes invocations of user-defined functions.
**
** When should functions be used?
Functions should be used to optimize processes
**
** Functions and Type Dependencies
Since SQL statements in the function body are not parsed during function creation, 
there are no dependencies on tables, views or materialized views, or other functions 
and stored procedures, which are used in the function body. For this reason, 
functions need only be recreated when needed as the result of an actual change, 
not simply due to a cascade drop.
**
Just as with materialized views, user-defined data types cannot be modified 
without being dropped first. To drop a type, all other user-defined types that 
include it as an element and all functions that depend
**
**
** Functions features
Parameterizing which is not available with Views
No Explicit Dependency on Table and Views
Ability to Execute Dynamic SQL
**
**
** Functions and Security
SECURITY DEFINER -> A function is executed with the permissions of the function creator.
SECURITY INVOKER (Default)-> A function is executed with the permissions of the executor. 
                This implicitly means, executor should have access to all the underlying objects used.
*/


create or replace function text_to_numeric(input_text text)
returns int as
$body$
BEGIN
    return replace(input_text,',','')::INT;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL::INT;
END;
$body$
LANGUAGE plpgsql;



SELECT text_to_numeric('1,000,990');
SELECT * from text_to_numeric('1,000,990');


-- User Defined Data Types
CREATE DOMAIN timeperiod  AS tstzrange;
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
CREATE TYPE mood_range AS RANGE...
CREATE TYPE <base type>

-- Define array of base type
DECLARE
    v_moods_set mood[];




-- Create composite type
    -- DROP TYPE boarding_pass_record CASCADE;
CREATE TYPE boarding_pass_record AS 
(
    boarding_pass_id int,
    booking_leg_id bigint,
    flight_no text,
    departure_airport text,
    arrival_airport text,
    last_name text,
    first_name text,
    seat text,
    boarding_time timestamptz
);

DECLARE
    v_new_boarding_pass_record boarding_pass_record;


/* To get type of SELECT result
** Add \gdesc in psql after SELECT
**
*/
postgres_air#

SELECT  pass_id,
            bp.booking_leg_id,
            flight_no,
            departure_airport::text ,
            arrival_airport ::text,
            last_name ,
            first_name ,
            seat,
            boarding_time
    FROM flight f
    JOIN booking_leg bl USING (flight_id)
    JOIN boarding_pass bp USING(booking_leg_id)
    JOIN passenger USING (passenger_id) \gdesc


/* Function returning all boarding passes for flight 
** */
CREATE OR REPLACE FUNCTION boarding_passes_flight (p_flight_id int)
RETURNS SETOF boarding_pass_record
AS
$body$
BEGIN
    RETURN QUERY
    SELECT  pass_id,
            bp.booking_leg_id,
            flight_no,
            departure_airport::text ,
            arrival_airport ::text,
            last_name ,
            first_name ,
            seat,
            boarding_time
    FROM flight f
    JOIN booking_leg bl USING (flight_id)
    JOIN boarding_pass bp USING(booking_leg_id)
    JOIN passenger USING (passenger_id)
    WHERE bl.flight_id=p_flight_id;
END;
$body$
LANGUAGE plpgsql;

SELECT * FROM boarding_passes_flight(13);
SELECT boarding_passes_flight(13);



CREATE OR REPLACE FUNCTION boarding_passes_pass (p_pass_id int)
RETURNS SETOF boarding_pass_record
AS
$body$
BEGIN
    RETURN QUERY
    SELECT  pass_id,
            bp.booking_leg_id,
            flight_no,
            departure_airport::text ,
            arrival_airport ::text,
            last_name ,
            first_name ,
            seat,
            boarding_time
    FROM flight f
    JOIN booking_leg bl USING (flight_id)
    JOIN boarding_pass bp USING(booking_leg_id)
    JOIN passenger USING (passenger_id)
    WHERE pass_id=p_pass_id;
END;
$body$
LANGUAGE plpgsql;

SELECT * FROM boarding_passes_pass(215158);



CREATE TYPE flight_record AS
(
    flight_id int,
    flight_no text,
    departure_airport_code text,
    departure_airport_name text,
    arrival_airport_code text,
    arrival_airport_name text,
    scheduled_departure timestamptz,
    scheduled_arrival timestamptz
);

CREATE TYPE booking_leg_record AS
(
    booking_leg_id int,
    leg_num int,
    booking_id int,
    flight flight_record,
    boarding_passes boarding_pass_record[]
);


/* Function with Nested Composites Types
** 
*/
CREATE OR REPLACE FUNCTION booking_leg_select (p_booking_leg_id int)
RETURNS SETOF booking_leg_record
AS
$body$
BEGIN
    RETURN QUERY
    SELECT  bl.booking_leg_id,
            leg_num,
            bl.booking_id,
            (SELECT row(flight_id,
                        flight_no,
                        departure_airport,
                        da.airport_name,
                        arrival_airport,
                        aa.airport_name ,
                        scheduled_departure,
                        scheduled_arrival
                    )::flight_record
            FROM flight f
            JOIN airport da on da.airport_code=departure_airport
            JOIN airport aa on aa.airport_code=arrival_airport
            WHERE flight_id=bl.flight_id
            ),
            (SELECT array_agg(
                        row(
                            pass_id,
                            bp.booking_leg_id,
                            flight_no,
                            departure_airport ,
                            arrival_airport,
                            last_name ,
                            first_name ,
                            seat,
                            boarding_time
                        )::boarding_pass_record
                    )
            FROM flight f1
            JOIN  boarding_pass bp ON f1.flight_id=bl.flight_id
                AND bp.booking_leg_id=bl.booking_leg_id
            JOIN passenger p ON p.passenger_id=bp.passenger_id
            )
    FROM booking_leg bl
    WHERE bl.booking_leg_id=p_booking_leg_id;
END;
$body$ language plpgsql;

SELECT * FROM booking_leg_select (17564910);

perform * from booking_leg_select (17564910);

