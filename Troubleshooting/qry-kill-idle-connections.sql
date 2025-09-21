-- Connection counts by username
SELECT usename, count(*) AS connection_count
FROM pg_stat_activity
GROUP BY usename
ORDER BY connection_count DESC;

-- Terminate Idle Connections
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle' AND usename != 'postgres';

