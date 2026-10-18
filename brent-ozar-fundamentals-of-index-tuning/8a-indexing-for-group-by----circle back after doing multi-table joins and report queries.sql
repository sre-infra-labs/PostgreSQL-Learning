/* Fundamentals of Index Tuning
 * Module X: How to Index for Group By
 * 
 * v0.1 - 2025-03-28
 * https://smartpostgres.com/fundamentals/index-tuning
 * 
 * This demo works on any version of Postgres,
 * but requires the large users table:
 * https://smartpostgres.com/go/querystack
 * 
 * Licensed under Creative Commons CC BY-SA 4.0
 * Attribution-ShareAlike 4.0 International:
 * https://creativecommons.org/licenses/by-sa/4.0/
 */


/* Start with no indexes: */
select * from drop_indexes('public', 'users');

/* Reporting queries often use group by for analysis, like
 * this query that finds the top locations:
 */
select u.location, count(*) as total_users, 
	max(reputation) as top_reputation,
	sum(reputation) as total_reputation,
	avg(reputation) as avg_reputation
from users u
group by u.location
order by count(*) desc limit 100;



/* Review the plan to see why it's slow: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.location, count(*) as total_users, 
	max(reputation) as top_reputation,
	sum(reputation) as total_reputation,
	avg(reputation) as avg_reputation
from users u
group by u.location
order by count(*) desc limit 100;


/* It's scanning the table,
 * then sorting all the rows by location.
 * 
 * The sort's input is unsorted because the data is coming
 * from the heap like this:
 */
select * from users order by ctid limit 100;


/* When data's coming in unsorted,
 * Postgres uses a hash aggregate to put the rows in order.
 * 
 * It would be faster if the input data was already sorted.
 * 
 * Like if we had an index: */
create index users_location on users(location);

/* Does it get used? */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.location, count(*) as total_users, 
	max(reputation) as top_reputation,
	sum(reputation) as total_reputation,
	avg(reputation) as avg_reputation
from users u
group by u.location
order by count(*) desc limit 100;


/* The index doesn't cover everything we need for the query,
 * and the query wants all the rows in the table,
 * so it's more efficient to ignore the index and do a heap scan.
 * 
 * Let's try expanding the index to include the columns we need:
 */
create index users_location_include on users(location) include (reputation);


/* Does it get used? */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.location, count(*) as total_users, 
	max(reputation) as top_reputation,
	sum(reputation) as total_reputation,
	avg(reputation) as avg_reputation
from users u
group by u.location
order by count(*) desc limit 100;



EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.location, sum(1) as total_users, 
	max(reputation) as top_reputation,
	sum(reputation) as total_reputation,
	avg(reputation) as avg_reputation
from users u
group by u.location
order by sum(1) desc limit 100;




EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.location, sum(1) as total_users
from users u
group by u.location
order by sum(1) desc limit 100;

select * from check_indexes('public', 'users');
select * from drop_indexes('public', 'users');

create index users_location on users(location);
/* Either:
 * 
 * 		Adding an index actually made the reads worse (higher), or
 * 
 * 		The explain plan is lying when it says how many buffer reads
 * 		were done by an "index-only scan"
 */

/* This does an index-only scan: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.location, sum(1) as recs
from users u
group by u.location
limit 100;

/* This does a heap scan: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.location, sum(1) as recs
from users u
group by u.location
order by sum(1) desc	/* <--------- changes everything */
limit 100;



select * from check_indexes(null, null)
order by size_kb desc;

select * from posts limit 100;

select * from check_indexes('public', 'posts');
create index posts_posttypeid on posts(posttypeid);

/* This does an index-only scan: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select p.title, sum(1) as recs
from posts p
group by p.title
limit 100;

/* This does a heap scan: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select p.title, sum(1) as recs
from posts p
group by p.title
order by sum(1) desc	/* <--------- changes everything */
limit 100;



/* */