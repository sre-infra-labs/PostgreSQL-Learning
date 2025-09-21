/* Using Dynamic SQL to Aid the Optimizer
**
**
*/


/* Listing 12-13. Selecting booking by email and departure airport
**
** Though email is restrictive enough, the optimizer fails to use the index on booking_id in
the second join.
**
** The reason for this suboptimal plan has been mentioned before—the PostgreSQL
optimizer does not estimate the size of intermediate result sets correctly.
**
*/
SELECT DISTINCT b.booking_id, b.booking_ref,
b.booking_name, b.email
FROM booking b
JOIN  booking_leg bl USING (booking_id)
JOIN flight f USING (flight_id)
WHERE lower(email) like 'lawton510%'
AND departure_airport='JFK';


-- Listing 12-14. Dynamic SQL to improve the code from Listing 12-13
-- drop function if exists select_booking_email_departure;
CREATE OR REPLACE FUNCTION select_booking_email_departure(p_email text, p_dep_airport text)
RETURNS TABLE (booking_id bigint, booking_ref text, booking_name text, email text)
    --SETOF booking_record_basic 
AS
$body$
DECLARE
    v_sql text;
    v_booking_ids text;
BEGIN
    -- Divide the query, and save booking_ids
    EXECUTE $$SELECT array_to_string(array_agg(booking_id), ',')
            FROM booking
            WHERE lower(email) like $$||quote_literal(p_email||'%')
            INTO v_booking_ids;

    v_sql := $$SELECT DISTINCT b.booking_id, b.booking_ref, b.booking_name, b.email
            FROM booking b
            JOIN  booking_leg bl USING(booking_id)
            JOIN flight f USING (flight_id)
            WHERE b.booking_id IN ($$||v_booking_ids||$$)
            AND departure_airport=$$||quote_literal(p_dep_airport);
    RETURN QUERY EXECUTE v_sql;
END;
$body$ LANGUAGE plpgsql;


SELECT * FROM select_booking_email_departure('lawton510','JFK')




