--EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select flight_id, departure_airport, arrival_airport
from postgres_air.flight
where scheduled_departure >= '2023-10-13' and scheduled_departure < '2023-10-14';

--EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select flight_id, departure_airport, arrival_airport
from postgres_air.flight
where scheduled_departure::date = '2023-10-13';