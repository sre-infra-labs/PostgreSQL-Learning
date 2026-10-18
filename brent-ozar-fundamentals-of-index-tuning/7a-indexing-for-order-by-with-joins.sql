/* Fundamentals of Index Tuning
 * Module X: How to Index for Order By - with Joins
 * 
 * v0.1 - 2025-03-31
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


/* In the earlier module on indexing for order by,
 * we used these indexes: */
select * from drop_indexes('public', 'users');

create index users_location_reputation_includes
	on users(location, reputation) include (websiteurl);

create index users_websiteurl_location on users(websiteurl, location);


/* To show how Postgres will use an index on the order-by
 * column if the where clause filters weren't selective: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location is not null
  and u.websiteurl is not null
order by u.reputation desc
limit 100;

/* But now, we're working with multi-table joins.
 * 
 * Let's take the multi-table query we've been using,
 * and the indexes we created to support its joins & filters.
 * 
 * Make sure we have our indexes on userid and creationdate:
 */
select * from check_indexes('public', 'comments');
create index comments_creationdate on comments(creationdate);
create index comments_userid on comments(userid);


/* This was the query we were working with: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.displayname, u.id, c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  and c.creationdate >= '2013-08-01'
  and c.creationdate < '2013-09-01';


/* 5 demos we'll do in this module:
 * 1. order by user table column
 * 2. order by comments table column
 * 3. order by user table column, then comments table column
 * 4. order by comments, then users
 * 5. order by calculated field that involves both tables
 */

/* Let's sort by the users reputation first.
 * Typically - but not always - when you're sorting
 * in the database, you're probably either paginating
 * or just getting the first X rows, so we'll add
 * limit 100 too: */

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.id, 
	c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  and c.creationdate >= '2013-08-01'
  and c.creationdate < '2013-09-01'
order by u.reputation desc
limit 100;

/* Back in the single-table module, we learned that
 * if we want to eliminate a sort on a single-table query,
 * we have to put the order by columns
 * AFTER the equality searches,
 * BEFORE the inequality searches, like this: */
select * from check_indexes('public', 'users');

create index users_location_reputation_includes
	on users(location, reputation) include (websiteurl);

/* Does that index get used? Is the sort still there? */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.id, 
	c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  and c.creationdate >= '2013-08-01'
  and c.creationdate < '2013-09-01'
order by u.reputation desc
limit 100;

/* That's odd, because it DOES get used in a single-table query: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.id
	--c.creationdate, c.score, c."text"
from users u
--join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  --and c.creationdate >= '2013-08-01'
  --and c.creationdate < '2013-09-01'
order by u.reputation desc
limit 100;


/* When we add the join back in, the sort reappears,
 * even though the users data IS sorted by reputation: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.id, 
	c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  and c.creationdate >= '2013-08-01'
  and c.creationdate < '2013-09-01'
order by u.reputation desc
limit 100;


/* Postgres decided to introduce parallelism into the query
 * to handle the large number of comments it expected.
 * 
 * If I distribute a sorted list among everybody here,
 * and I have you all work on your portions individually,
 * then I'm gonna wanna distribute the work kind of evenly.
 * 
 * I may break things up out of order (like in a hash)
 * so I can more evenly distribute the work across all of you.
 * 
 * And, when you turn things back in, they may not be turned
 * in in order either - some of you will get done quickly,
 * some slowly. (I'm not naming names, but we all know who
 * the slow one is here, right? Not you. It's the one next to you.)
 * 
 * So after data comes back from a parallel operation like
 * a hash join, if we need it returned in order, then we're
 * gonna need to sort it - regardless of whether it came in
 * sorted or not.
 * 
 * Just because we asked for a join
 * doesn't mean it has to be a hash join,
 * and doesn't mean is has to go parallel.
 * 
 * But if we have a lot of data, it's probably gonna be
 * a hash join, and it's probably gonna go parallel,
 * which means we're gonna have to have that sort.
 * 
 * 
 * But just theoretically speaking...
 * 
 * Let's say you worked for a fast-paced online site where
 * every millisecond mattered.
 * 
 * And let's say, just to say, that you have small queries
 * on small amounts of data, like on a user's particular
 * profile page.
 * 
 * Let's make our where clause a lot more selective.
 * Instead of this:
 */

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.id, 
	c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  and c.creationdate >= '2013-08-01'
  and c.creationdate < '2013-09-01'
order by u.reputation desc
limit 100;

/* Let's make the filters much more selective: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.id, 
	c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  and c.creationdate >= '2013-08-13'
  and c.creationdate < '2013-08-14'	/* this is shorter, just one day */
order by u.reputation desc
limit 100;

/* Things to discuss:
 * 		Did the query go parallel?
 * 		How many comments were involved?
 * 		Did Postgres choose a hash join?
 * 		Did we end up with a sort? Why?
 * 
 * Let's try an even 
 */

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.id, 
	c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  and c.creationdate >= '2013-08-13 13:00'
  and c.creationdate < '2013-08-14 14:00'	/* just one hour */
order by u.reputation desc
limit 100;


/* Any better? Keep narrowing our filters: */


EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.id, 
	c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl = 'http://careers.stackoverflow.com/jonik'	/* just one person */
  and c.creationdate >= '2013-08-13 13:00'
  and c.creationdate < '2013-08-14 14:00'	/* just one hour */
order by u.reputation desc
limit 100;


/* Things to discuss:
 * 		Did that change the query's order of operations - which table gets read first?
 *		Did that change the join type?
 *		Do we still have a sort?
 *
 *
 * Takeaways: even when you're dealing with a pretty small amount of data,
 * and even when Postgres knows it's a small amount of data,
 * you're still probably going to end up with sorts after data is joined
 * between multiple tables.
 * 
 * And that's okay, because most of the time, sorting the data after you find it
 * is the least of your problems.
 * 
 * Your problem is usually finding the data.
 * 
 * If you have that many end result rows to sort,
 * and the ending sort is the biggest problem you're facing,
 * it's time to consider moving the sort to the application.
 * 
 * Pull the result rows down locally to your application (C#, Java, Python, etc)
 * and sort the rows there.
 */
