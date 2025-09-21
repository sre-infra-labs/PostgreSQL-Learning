set
    search_path to postgres_air;

/*  Query that is good candidate for partial index
*/
SELECT * FROM flight WHERE
    scheduled_departure between '2020-08-15' AND '2020-08-18'
    AND status='Canceled';

-- Partial Index
CREATE INDEX flight_canceled ON flight(flight_id)
WHERE status='Canceled';