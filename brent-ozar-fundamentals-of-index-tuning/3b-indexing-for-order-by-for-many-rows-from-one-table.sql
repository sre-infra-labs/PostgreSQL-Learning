/* Fundamentals of Index Tuning
 * Module 3b: How to Index for Order By - for Many Rows from One Table
 * 
 * v1.0 - 2025-04-07
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


/* start with the indexes that were helping our location/website search: */
select * from drop_indexes('public', 'users');
create index users_location on users(location);
create index users_websiteurl on users(websiteurl);
create index users_reputation on users(reputation);
select * from check_indexes('public', 'users');


/* Earlier we were finding the top-scoring (reputation)
 * users from a particular area, like this: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> ''
order by u.reputation desc
limit 100;


/* And Postgres didn't use the index on reputation.
 * 
 * BUT...
 * 
 * What if our where clause filters aren't selective at all?
 * What if they don't really reduce our search space?
 *  
 * For example, let's say we're building a leaderboard
 * for all of Stack Overflow's users that have filled
 * in their profiles, and our query looks like this:
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location is not null
  and u.websiteurl is not null
order by u.reputation desc
limit 100;

/* Does the index on reputation get used?
 * How much data was read from buffers?
 * Does our query have a sort in it?
 */

/* To understand what happens in the explain plan, 
 * let's read the contents of the index: */
select u.reputation, u.ctid
from users u 
order by u.reputation desc
limit 100;


/* Postgres had to check the heap for each user to see its location & websiteurl,
 * which would end up producing these results: */
select u.reputation as reputation_from_index, u.ctid, u.location as location_from_heap, u.websiteurl as website_from_heap
from users u 
order by u.reputation desc
limit 100;



/* Takeaway:
 * If your query's "where" filters are NOT selective,
 * AND your query has an order by,
 * AND your query returns a limited number of rows...
 * 
 * Then an index on the order by columns is like a filter.
 * Most of the rows in our "limit 100" will match our where clause,
 * so Postgres will use the index on the order by columns.
 * 
 * 
 * 
 * 
 * What if we try getting more rows?
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location is not null
  and u.websiteurl is not null
order by u.reputation desc
limit 1000;


/* Or more: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location is not null
  and u.websiteurl is not null
order by u.reputation desc
limit 10000;


/* Or even more: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location is not null
  and u.websiteurl is not null
order by u.reputation desc
limit 100000;


/* How about ... ONE MILLION ... (insert pinky finger in mouth) */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location is not null
  and u.websiteurl is not null
order by u.reputation desc
limit 1000000;



/* Or, let's go back to limit 100, and let's change our
 * query's filters. Instead of searching for non-selective
 * locations & websiteurls, let's search for selective ones:
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'India'
  and u.websiteurl = ''
order by u.reputation desc
limit 100;

/* Things to discuss:
 * 		Where did we read from?
 * 		Where did we check location & websiteurl?
 * 		Total amount of reads: ~280MB
 * 
 * Visualize what Postgres is doing:
 */
select u.reputation as reputation_from_index, u.ctid, u.location as location_from_heap, u.websiteurl as website_from_heap
from users u 
order by u.reputation desc
limit 100;


/* When our filter was NOT selective, like this, most of our rows matched: */
where u.location is not null
  and u.websiteurl is not null
  
/* But now that our filter IS selective, most of the rows do NOT match,
 * so we have to read a lot more rows from the index, check them in the heap, and keep going:
 */
where u.location = 'India'
  and u.websiteurl = ''

/* We could reduce that by adding location & websiteurl
 * to the definition of the index.
 * 
 * The data doesn't have to be sorted in the key,
 * we can just include it in the index,
 * because our goal is just to read less data overall.
 * 
 * Before:
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'India'
  and u.websiteurl = ''
order by u.reputation desc
limit 100;

/* Buffers: ~38,000
 * Size: ~300MB
 * 
 * Create an index with our where clause filters included:
 */
create index users_reputation_includes on users(reputation)
	include (location, websiteurl);


EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'India'
  and u.websiteurl = ''
order by u.reputation desc
limit 100;

/* Did Postgres use our index? Why not? Is it larger? */
select index_name, index_type, index_definition, size_kb 
from check_indexes('public', 'users')
where index_name like 'users_reputation%';


/* What if we didn't have the index on reputation alone? */
drop index users_reputation;

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'India'
  and u.websiteurl = ''
order by u.reputation desc
limit 100;

/* Things to discuss:
 * Where did Postgres read the data from?
 * Did our reads go up or down?
 * How much buffers were read, as opposed to the total index size?
 */





/* But not all filters will use it: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'India'
  and u.websiteurl = 'http://none'
order by u.reputation desc
limit 100;

/* It will be different depending on your particular query's filters' selectivity. 
 * 
 * So far, we've been working with single-table queries.
 * The answers get more complicated as we add joins,
 * and we'll revisit this after we join more tables together.
 * 
 * 
 * 
 * Takeaways:
 * 
 * Normally we think about the where clause as the main filters.
 * 
 * But if your where clause isn't selective,
 * and the query has an order by and a limit,
 * try indexing on the order-by columns (in order).
 * 
 * You may also have to add the where clause filters to the index,
 * and they can be in the include columns (rather than keys)
 * if the sort order isn't all that useful.
 */

