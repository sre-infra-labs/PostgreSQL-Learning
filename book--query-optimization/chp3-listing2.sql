
--select inet_server_addr(), inet_server_port();

set search_path to postgres_air;

-- Large dataset in result. Low selectivity.
--EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select flight_no, departure_airport, arrival_airport
from postgres_air.flight
where scheduled_departure between '2023-05-15' and '2023-08-31';

-- Small dataset in result. High selectivity.
--EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select flight_no, departure_airport, arrival_airport
from postgres_air.flight
where scheduled_departure between '2023-08-12' and '2023-08-13';