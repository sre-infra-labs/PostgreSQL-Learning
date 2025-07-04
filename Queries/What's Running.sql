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
    a.pid AS process_id,
    a.state,
    a.query,
    a.query_start,
    a.wait_event_type,
    a.wait_event,
    a.backend_type,
    a.client_addr,
    blocking_info.locked_by
FROM pg_stat_activity AS a
LEFT JOIN blocking_info ON a.pid = blocking_info.pid
WHERE a.state != 'idle'
AND query NOT ILIKE '%pg_stat_activity%' 
ORDER BY a.query_start DESC;

