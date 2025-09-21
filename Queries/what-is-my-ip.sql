SELECT
    inet_server_addr() AS server_ip,
    --inet_server_hostname() AS server_hostname,
    current_database() AS database_name,
    pg_postmaster_start_time() AS server_start_time,
    now() - pg_postmaster_start_time() AS uptime,
    version() AS pg_version,
    pg_is_in_recovery() AS is_standby,
    current_setting('data_directory') AS pgdata,
    current_setting('cluster_name') AS cluster_name,
    current_setting('max_connections')::int AS max_connections,
    current_setting('port')::int AS configured_port,
    inet_server_addr() || ':' || inet_server_port() AS server_address
;

show primary_conninfo;

SELECT
    usename,
    client_addr,
    client_hostname,
    application_name,
    state,
    sync_state,
    backend_start,
    sent_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;

SELECT
    client_addr,
    client_hostname,
    application_name
FROM pg_stat_activity
WHERE client_addr IS NOT NULL
  AND application_name LIKE '%wal%';