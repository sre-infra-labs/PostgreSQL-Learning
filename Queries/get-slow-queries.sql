/*  https://www.cybertec-postgresql.com/en/find-and-fix-a-missing-postgresql-index/
    https://www.postgresql.org/docs/current/pgstatstatements.html#PGSTATSTATEMENTS
*/
-- Top top 10 long running queries
SELECT round((100 * total_exec_time / sum(total_exec_time)
        OVER ())::numeric, 2) percent,
        round(total_exec_time::numeric, 2) AS total,
        calls,
        round(mean_exec_time::numeric, 2) AS mean,
        substring(query, 1, 200)
 FROM  pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

--create extension pg_stat_statements;