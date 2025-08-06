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

WITH base AS (
  SELECT
    -- COALESCE(application_name, 'unknown') AS application,
    usename AS username,
    COALESCE(client_hostname, client_addr::text, 'local') AS client,
    COALESCE(datname, 'unknown') as datname,
    COUNT(*) AS conn_count
  FROM pg_stat_activity
  GROUP BY username, client, datname
),
totals AS (
  SELECT
    SUM(conn_count) AS total_conns
  FROM base
),
user_totals AS (
  SELECT
    username,
    SUM(conn_count) AS total_user_conns
  FROM base
  GROUP BY username
),
client_totals AS (
  SELECT
    client,
    SUM(conn_count) AS total_client_conns
  FROM base
  GROUP BY client
),
database_totals AS (
  SELECT
    datname,
    SUM(conn_count) AS total_database_conns
  FROM base
  GROUP BY datname
)
SELECT
--   b.application,
  b.username,
  b.client,
  b.datname,
  b.conn_count,
  u.total_user_conns,
  c.total_client_conns,
  d.total_database_conns
FROM base b
-- JOIN totals t ON b.application = t.application
JOIN user_totals u ON b.username = u.username
JOIN client_totals c ON b.client = c.client
JOIN database_totals d on d.datname = b.datname
ORDER BY u.total_user_conns DESC, d.total_database_conns desc, c.total_client_conns DESC;

/*
SHOW max_connections;
SHOW superuser_reserved_connections;

SELECT usesuper, usename FROM pg_stat_activity WHERE pid = pg_backend_pid();
*/