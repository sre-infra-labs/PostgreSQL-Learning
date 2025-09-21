-- https://www.youtube.com/watch?v=gzktbdp2pDE&ab_channel=SmartPostgres
-- https://explain.dalibo.com/plan/505d9312dcf524b9
-- https://github.com/SmartPostgres/Box-of-Tricks/blob/dev/checks/check_indexes.sql

/* Meet the StackOverflow users table */
select * from public.users limit 100;

select * from public.users where location = 'Las Vegas, NV, USA';


/* Find the highest ranking users */
select *
from public.users
where location = 'Las Vegas, NV, USA'
order by reputation desc
limit 100;


/* Find the highest ranking users */
explain
select *
from public.users
where location = 'Las Vegas, NV, USA'
order by reputation desc
limit 100;

-- https://explain.dalibo.com/
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select *
from public.users
where location = 'Las Vegas, NV, USA'
order by reputation desc
limit 100;

-- create supporting index
create index users_location_reputation on public.users (location, reputation);

-- https://explain.dalibo.com/
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select *
from public.users
where location = 'Las Vegas, NV, USA'
order by reputation desc
limit 100;

-- https://explain.dalibo.com/
   -- ctid => internal column. Tuple Identifier. (page, row)
select ctid, xmin, xmax, *
from public.users
where location = 'Las Vegas, NV, USA'
order by reputation desc
limit 100;

-- Check indexes
select * from check_indexes('public','users')


