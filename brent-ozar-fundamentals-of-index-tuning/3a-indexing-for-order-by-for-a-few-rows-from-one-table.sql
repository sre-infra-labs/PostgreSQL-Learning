/* Fundamentals of Index Tuning
 * Module 3a: How to Index for Order By - for a Few Rows from One Table
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


/* start with the indexes that help this query: */
select * from drop_indexes('public', 'users');
create index users_location on users(location);
create index users_websiteurl on users(websiteurl);
select * from check_indexes('public', 'users');


/* Say I want to find the top Reputation users in a particular location, 
 * who have filled out their URL: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
order by u.reputation desc
limit 100;


/* That query's really fast.
 * 
 * We don't have a separate index on reputation - and we don't need it.
 * 
 * Even if we HAD it, Postgres won't use it for queries like this:
 */
create index users_reputation on users(reputation);

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
order by u.reputation desc
limit 100;


/* Right now, that query plan has a sort on reputation.
 * 
 * Could we remove that by adding reputation to the index it's using?
 */
create index users_location_reputation on users(location, reputation);
/* Drop the old narrower index: */
drop index users_location;


/* Rerun the query and check for a sort: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
order by u.reputation desc
limit 100;


/* Postgres no longer has a sort in the plan because our data
 * is already sorted by location, then reputation.
 * 
 * What if my query asked for TWO locations:
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location in ('Helsinki, Finland', 'Las Vegas, NV')
  and u.websiteurl is not null
order by u.reputation desc
limit 100;


/* Now we have a sort in the plan because the data's coming
 * from two separate areas of the index: the group of Helsinki
 * users, and the group of Las Vegas users.
 * 
 * If we looked at the contents of the index, it's organized
 * like this:
 */
select u.location, u.reputation, u.ctid
from users u
where u.location in ('Helsinki, Finland', 'Las Vegas, NV')
  and u.websiteurl is not null
order by u.location, u.reputation;

/* So we have to sort the Helsinki and Vegas people together
 * after we've found them.
 * 
 * Before, when we were looking for location EQUALS Helsinki,
 * adding the order-by column to the end of the index removed
 * the sort from the plan.
 * 
 * Now, when we're doing an INequality search,
 * meaning we're looking for multiple values or a range
 * of different locations, then we can't remove the sort
 * simply by tacking on the order-by columns to the end of
 * the index.
 * 
 * Takeaway:
 * 
 * If your query is only using EQUALITY searches,
 * and you want to make it faster by removing the sort,
 * you can add the order-by columns to the end of the index keys.
 * 
 * If your query is doing INequality searches, you can't.
 */




/* We were tuning this, and saying that location is an
 * equality search, and it's indexed: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
order by u.reputation desc
limit 100;


/* What if we change the websiteurl filter a little: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> ''					/* CHANGED */
order by u.reputation desc
limit 100;



/* That sucks.
 *
 * That's why when we're dealing with a single-table query,
 * with only a few (or a few thousand) rows,
 * you won't usually see people trying to remove the sort
 * with index tuning. 
 * 
 * You can try, it just isn't likely to work consistently
 * in real-world situations because real-world queries
 * usually involve inequality searches.
 * 
 * There are still situations where indexing helps with
 * order by & sorts, but it's just not when we're talking
 * about small queries on a single small table, like this.
 */