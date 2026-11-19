/*  Some links with Queries 
**  https://gist.github.com/mencargo/79447185034ebabcb49087008fbdc266#table-sizes
**  Youtube - Deep Dive on Amazon Aurora PostgreSQL Performance Tuning - https://youtu.be/XKPHbYe-fHQ
*/

-- get user connect server and port. Would be null for Unix socket connections
select  pg_postmaster_start_time(), 
        date_trunc('second', current_timestamp - pg_postmaster_start_time()) as uptime,
        inet_server_addr(), inet_server_port();

-- vacuum command
VACUUM (VERBOSE, ANALYZE);

-- all database users
select * from pg_stat_activity where query not like '<%';

-- all databases and their sizes
select * from pg_user;

-- cache hit rates (should not be less than 99% for OLTP systems)
SELECT sum(heap_blks_read) AS heap_read,
       sum(heap_blks_hit) AS heap_hit,
       ROUND(sum(heap_blks_hit) * 100.0 / (sum(heap_blks_hit) + sum(heap_blks_read)), 2) AS cache_hit_ratio
FROM   pg_statio_user_tables;

-- how many indexes are in cache
SELECT sum(idx_blks_read) as idx_read, sum(idx_blks_hit)  as idx_hit, (sum(idx_blks_hit) - sum(idx_blks_read)) / sum(idx_blks_hit) as ratio
FROM pg_statio_user_indexes;


-- Restart all sequences
SELECT 'ALTER SEQUENCE ' || relname || ' RESTART;' FROM pg_class WHERE relkind = 'S';

-- Dump database on remote host to file
$ pg_dump -U username -h hostname databasename > dump.sql

-- Import dump into existing database
$ psql -d newdb -f dump.sql


-- Backup cluster objects only, that  is, intra cluster objects like roles, tablespaces, replication slots etc
$ pg_dumpall --globals-only -f /tmp/$HOSTNAME\_cluster.sql
