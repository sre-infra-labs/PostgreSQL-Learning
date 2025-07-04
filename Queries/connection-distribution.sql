-- SHOW max_connections;
-- SHOW superuser_reserved_connections;

WITH settings AS (
    SELECT
        current_setting('max_connections')::int AS max_conn,
        current_setting('superuser_reserved_connections')::int AS reserved
),
conn AS (
    SELECT
        COUNT(*) AS total_conn,
        COUNT(*) FILTER (WHERE usename = 'postgres') AS superuser_conn
    FROM pg_stat_activity
)
SELECT
    s.max_conn,
    s.reserved,
    c.total_conn,
    c.superuser_conn,
    s.max_conn - s.reserved AS regular_slots,
    s.max_conn - c.total_conn AS free_slots,
    GREATEST(0, s.reserved - c.superuser_conn) AS free_reserved_slots
FROM settings s, conn c;

SELECT
  usename AS username,
  COALESCE(client_hostname, client_addr::text, 'local') AS client,
  datname,
  COUNT(*) AS connection_count,
  --GROUPING(application_name) AS g_app,
  GROUPING(usename) AS g_user,
  GROUPING(client_hostname, client_addr) AS g_client,
  GROUPING(datname) AS g_db
FROM pg_stat_activity
GROUP BY GROUPING SETS (
  ( usename, client_hostname, client_addr, datname),
  (usename),
  (client_hostname, client_addr),
  (datname)
)
ORDER BY
  GROUPING(usename),
  GROUPING(client_hostname, client_addr),
  GROUPING(datname);

/*
SHOW max_connections;
SHOW superuser_reserved_connections;

SELECT usesuper, usename FROM pg_stat_activity WHERE pid = pg_backend_pid();
*/