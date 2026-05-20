
\l
\c scratchpad

CREATE ROLE scratchpad WITH LOGIN PASSWORD 'scratchpad'
    VALID UNTIL '2025-10-08 12:26:00';


export PGPASSWORD='scratchpad'
psql -h localhost -U scratchpad -d scratchpad

select current_timestamp, current_user;
\watch 5
