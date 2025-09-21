/* Dynamic SQL
**
Dynamic SQL is any SQL statement that is first built as a text string and then executed
using the EXECUTE command.
**
** In PostgreSQL, execution plans are not cached even for prepared queries
    (i.e., queries that are preparsed, analyzed, and rewritten using the PREPARE command)
That means that optimization always happens immediately before execution.
*/

-- Listing 12-1. Dynamic SQL
DECLARE
    v_sql text;
    cnt int;
BEGIN
    v_sql := $$SELECT count(*) FROM booking WHERE booking_ref='0Y7W22'$$;
    EXECUTE (v_sql) into cnt;
    RAISE NOTICE 'v_sql: %', v_sql;
    RAISE NOTICE 'Count: %', cnt;
END



-- Listing 12-2. Create a return type
DROP TYPE IF EXISTS booking_leg_part ;
CREATE TYPE booking_leg_part AS
(
    departure_airport char (3),
    booking_id int,
    is_returning boolean
);

-- Listing 12-3. SQL from Listing 6-6, packaged in a function
CREATE OR REPLACE FUNCTION select_booking_leg_country ( p_country text, p_updated timestamptz )
RETURNS SETOF booking_leg_part
AS
$body$
BEGIN
    RETURN QUERY
    SELECT departure_airport, booking_id, is_returning
    FROM booking_leg bl
    JOIN flight f USING (flight_id)
    WHERE departure_airport IN (SELECT airport_code FROM airport WHERE iso_country=p_country)
        AND bl.booking_id IN (SELECT booking_id FROM booking WHERE update_ts>p_updated);
END;
$body$
LANGUAGE plpgsql;

-- Raw query used in above function
EXPLAIN
SELECT departure_airport, booking_id, is_returning
FROM booking_leg bl
JOIN flight f USING (flight_id)
WHERE departure_airport IN (SELECT airport_code FROM airport WHERE iso_country='US')
    AND bl.booking_id IN (SELECT booking_id FROM booking WHERE update_ts>'2023-07-01');

-- Raw query used in above function
EXPLAIN
SELECT departure_airport, booking_id, is_returning
FROM booking_leg bl
JOIN flight f USING (flight_id)
WHERE departure_airport IN (SELECT airport_code FROM airport WHERE iso_country='US')
    AND bl.booking_id IN (SELECT booking_id FROM booking WHERE update_ts>'2023-08-15');


-- Listing 12-6. Examples of function calls
-- #1
SELECT * FROM select_booking_leg_country('US', '2023-07-01');
-- #2
SELECT * FROM select_booking_leg_country('US', '2023-08-01');
-- #3
SELECT * FROM select_booking_leg_country('US', '2023-08-15');
-- #4
SELECT * FROM select_booking_leg_country('CZ', '2023-08-01');


-- Listing 12-7. A function that executes dynamic SQL
    -- Version 01
CREATE OR REPLACE FUNCTION select_booking_leg_country_dynamic (p_country text, p_updated timestamptz)
RETURNS setof booking_leg_part
AS
$body$
BEGIN
    RETURN QUERY
    EXECUTE $$
        SELECT departure_airport, booking_id, is_returning
        FROM booking_leg bl
        JOIN flight f USING (flight_id)
        WHERE departure_airport IN (SELECT airport_code FROM airport WHERE iso_country= $$||quote_literal(p_country)||$$)
            AND bl.booking_id IN (SELECT booking_id FROM booking WHERE update_ts>$$||quote_literal(p_updated)||$$)
    $$;
END;
$body$
LANGUAGE plpgsql;


-- Listing 12-7. A function that executes dynamic SQL
    -- Version 02
CREATE OR REPLACE FUNCTION select_booking_leg_country_dynamic(p_country TEXT, p_updated TIMESTAMPTZ)
RETURNS SETOF booking_leg_part
AS
$body$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := $$
        SELECT departure_airport, booking_id, is_returning
        FROM booking_leg bl
        JOIN flight f USING (flight_id)
        WHERE departure_airport IN (
            SELECT airport_code 
            FROM airport 
            WHERE iso_country = $$ || quote_literal(p_country) || $$)
            AND bl.booking_id IN (
                SELECT booking_id 
                FROM booking 
                WHERE update_ts > $$ || quote_literal(p_updated) || $$)
    $$;
    RAISE NOTICE 'v_sql: %', v_sql;
    RETURN QUERY EXECUTE v_sql;
END;
$body$
LANGUAGE plpgsql;

-- Listing 12-6. Examples of function calls
-- #1
SELECT * FROM select_booking_leg_country_dynamic('US', '2023-07-01');
-- #2
SELECT * FROM select_booking_leg_country_dynamic('US', '2023-08-01');
-- #3
SELECT * FROM select_booking_leg_country_dynamic('US', '2023-08-15');
-- #4
SELECT * FROM select_booking_leg_country_dynamic('CZ', '2023-08-01');


