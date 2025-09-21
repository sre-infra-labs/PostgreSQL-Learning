/*

session_preload_libraries = 'auto_explain'    # (no restart needed)

    auto_explain.log_min_duration = '1s'
    auto_explain.log_analyze = on

shared_preload_libraries = 'pg_stat_statements'    # (change requires restart)

1) pg_state_statements
-> Helps in figuring out the most expensive queries

2) auto_explain
-> Helps in figuring out the most expensive queries
-> It will log the query plan of slow queries
-> It will log the query plan of queries that take longer than a specified threshold
-> It will log the query plan of queries that are executed more than a specified number of times
*/