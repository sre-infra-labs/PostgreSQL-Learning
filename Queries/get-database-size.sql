-- Get database size
SELECT d.datname as database_name, pg_size_pretty(pg_database_size(d.datname)) AS database_size
FROM pg_database d
WHERE d.datistemplate = false
ORDER BY pg_database_size(d.datname) DESC;