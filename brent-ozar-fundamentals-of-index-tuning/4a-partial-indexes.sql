/* Fundamentals of Index Tuning
 * Module 4a: When to Use Partial Indexes
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



/* We've been tuning this query: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> ''
order by u.reputation desc
limit 100;

/* And we created these indexes: */
select * from drop_indexes('public', 'users');
create index users_location on users(location);
create index users_websiteurl on users(websiteurl);
create index users_reputation on users(reputation);

/* Our buffer metrics:
 * Index scan: ~10
 * Heap: ~2200
 */

/* Partial indexes are index with a where clause, like this: */
create index users_location_partial
	on users(location)
	where websiteurl <> '';

/* One benefit is that they only cause overhead on
 * inserts, updates, and deletes for rows that match
 * their filter.
 * 
 * If we do inserts, updates, and deletes for rows
 * that did NOT put in their websiteurl, then those
 * rows won't suffer from slower inserts/updates/dels
 * because we don't have to maintain them in our
 * partial index.
 * 
 * That also means the partial index is smaller:
 */
select * from check_indexes('public', 'users')
where index_name like 'users_location%';

/* Will Postgres use the index for our query? */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> '' 
order by u.reputation desc
limit 100;

/* Things to consider:
 * 		Does Postgres read from the partial index?
 * 		Are our reads lower?
 * 		Why are they lower?
 */

select * from check_indexes('public', 'users')
where index_name like 'users_location%';


/* This partial index's benefits:
 * 		It's smaller because it has less rows (assuming that the filter
 * 			is highly selective, like ours is, about 10% of rows match.)
 * 		It's smaller because it doesn't have websiteurl in it.
 * 		However, queries can still filter on websiteurl IF their filter
 * 			matches the partial index's filter, like ours does.
 * 
 * What if the query was filtering on the websiteurl text?
 */

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl like '%google.com%'
order by u.reputation desc
limit 100;

/* Which index gets used? 
 * 
 * 
 * What if that index wasn't there? Will Postgres use the partial index?
 */
drop index users_location;


EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl like '%google.com%'
order by u.reputation desc
limit 100;


/* Theoretically, Postgres could use this index to find the people
 * in Helsinki, then check the heap to see their location:
 */
create index users_location_partial
	on users(location)
	where websiteurl <> '';


/* However, the kind, helpful folks who volunteer their time
 * building the Postgres database engine don't seem to have
 * coded their query planner to accommodate this use case.
 * 
 * The documentation explains that Postgres doesn't put
 * a ton of effort into mathematically checking your query's
 * filters to see if they match (or are a subset of) the
 * partial index's filters:
 * https://www.postgresql.org/docs/current/indexes-partial.html
 */


/* Takeaways:
 * If you only care about a small subset of the data,
 * and your queries' WHERE clauses are consistent and clear,
 * then partial indexes can:
 * 
 * Reduce the size of your indexes on disk
 * 
 * Still make queries go faster (despite being smaller)
 * 
 * Reduce the index's overhead for inserts/updates/deletes
 * for rows you don't care about, because they're excluded
 * from your partial index, so we don't have to maintain
 * the index for those inserts/updates/deletes.
 * 
 * Just test to make sure they actually get used.
 */