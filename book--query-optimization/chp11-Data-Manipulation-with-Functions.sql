/* Data Manipulation with Functions
** 
**
*/

-- listing 11-22. Create a new boarding pass
CREATE OR REPLACE FUNCTION issue_boarding_pass
    (p_booking_leg_id int, p_passenger_id int, p_seat text, p_boarding_time timestamptz)
RETURNS SETOF boarding_pass_record
AS
$body$
    DECLARE
        v_pass_id int;
    BEGIN
        INSERT INTO boarding_pass
            (passenger_id, booking_leg_id, seat, boarding_time, update_ts)
        VALUES (p_passenger_id, p_booking_leg_id, p_seat, p_boarding_time, now())
        RETURNING pass_id INTO v_pass_id;
        
        RETURN QUERY
        SELECT  * FROM boarding_passes_pass(v_pass_id);
    END;
$body$
LANGUAGE plpgsql;

-- Create a boarding pass using function call
SELECT * FROM issue_boarding_pass(175820,462972, '22C', '2020-06-16  21:45'::timestamptz)