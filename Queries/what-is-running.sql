-- What is running right now
WITH blocking_info AS (
    SELECT 
        pid,
        string_agg(pg_blocking_pids(pid)::TEXT, ', ') AS locked_by
    FROM pg_stat_activity
    GROUP BY pid
)
SELECT age(clock_timestamp(), a.query_start) as query_duration,
    a.datname AS database_name,
    a.usename AS user_name,
	a.wait_event_type,
    a.wait_event,
    a.pid AS process_id,
    a.state,
    a.backend_start,
    a.xact_start,
    a.query_start,
    a.state_change,
    now()::time - a.state_change::time AS locked_since,
    a.backend_type,
    a.client_addr,
    blocking_info.locked_by,
	a.query
FROM pg_stat_activity AS a
LEFT JOIN blocking_info ON a.pid = blocking_info.pid
WHERE 1=1
and a.wait_event_type not in ('Activity')
and a.state != 'idle'
AND query NOT ILIKE '%pg_stat_activity%'
--AND wait_event_type IS NOT NULL
ORDER BY a.state_change asc;
--ORDER BY locked_since DESC;

/*
select l.*
from pg_locks l
join pg_stat_activity a
    on a.pid = l.pid
where 1=1
and a.pid in (258887,89099)
and 1=1;
*/



\x

SELECT pid,usename, datname, client_addr, application_name, state, backend_start, query_start, now() - query_start AS duration, query
FROM pg_stat_activity
WHERE state = 'active'
AND usename <> 'postgres'
ORDER BY duration DESC;
