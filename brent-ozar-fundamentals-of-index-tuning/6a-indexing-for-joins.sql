/* Fundamentals of Index Tuning
 * Module X: How to Index for Joins
 * 
 * v0.1 - 2025-03-28
 * https://smartpostgres.com/fundamentals/index-tuning
 * 
 * This demo works on any version of Postgres,
 * but requires the large users and comments tables:
 * https://smartpostgres.com/go/querystack
 * 
 * Licensed under Creative Commons CC BY-SA 4.0
 * Attribution-ShareAlike 4.0 International:
 * https://creativecommons.org/licenses/by-sa/4.0/
 */



/* Start with indexes similar to what we've used so far: */
select * from drop_indexes('public', 'users');
create index users_location on users(location);
create index users_websiteurl on users(websiteurl);



/* We've been optimizing this query so far: */
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
order by u.reputation desc
limit 100;

/* Let's change it a little and find the comments from Helsinki users: */
select u.displayname, u.id, c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null;



/* That's really two queries: */
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null;


from comments c
where c.userid in (a list of user.ids from the above query)


/* So to make that comments query fast, I need an index on userid: */
select * from check_indexes('public', 'comments');
create index comments_userid on comments(userid);


/* Run the query and see if Postgres uses it: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.displayname, u.id, c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null;


/* Things to review:
 * 		When reading a plan on Dalibo, look for the time icon
 * 		Where did the comments data come from?
 * 		How many buffers were read?
 * 		Is that smaller than the size of the table, indicating good index usage?
 */
select * from check_indexes('public', 'comments');


/* Takeaway: whatever columns you join, you probably want to index.
 * In this case:
 */
join comments c on u.id = c.userid

/* Both sides (user and comments) probably need indexes as a starting point.
 * This isn't a finishing line, it's just a good starting point.
 * 
 * 
 * Moving on... was the explain plan shaped by how we wrote the query?
 * If I turn the query around from this:
 */
from users u
join comments c on u.id = c.userid

/* To this: */
from comments c
join users u on c.userid = u.id

/* Does that change the plan's shape or metrics? */

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.displayname, u.id, c.creationdate, c.score, c."text"
from comments c
join users u on c.userid = u.id
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null;



/* Let's make things a little more complicated.
 * 
 * Let's add a where clause that looks for comments left
 * in a specific date range:
 */

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.displayname, u.id, c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  and c.creationdate >= '2013-08-01'
  and c.creationdate < '2013-09-01';


/* We don't have an index that leads on creationdate right now: */
select * from check_indexes('public', 'comments');
drop index comments_creationdate;


/* So what happens? */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.displayname, u.id, c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  and c.creationdate >= '2013-08-01'
  and c.creationdate < '2013-09-01';

/* Run it a couple of times, and note the duration.
 * 
 * What happens if I add an index on comments by creationdate?
 * Takes a minute or two to create: */
create index comments_creationdate on comments(creationdate);


/* Which index will Postgres use? Will it be faster? Does it read less data? */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.displayname, u.id, c.creationdate, c.score, c."text"
from users u
join comments c on u.id = c.userid
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
  and c.creationdate >= '2013-08-01'
  and c.creationdate < '2013-09-01';


/* When Postgres builds the plan, it thinks about which filter (users or comments)
 * is more selective, and which index will help it read less data overall.
 * 
 * This kind of thing isn't always accurate - planners make mistakes.
 * (You know how it goes - think about your own project managers.)
 * 
 * That's why indexing the columns you join on is a good starting point,
 * but not the finishing line.
 * 
 * You still need to index the columns you filter on.
 * 
 * Your lab exercise involves looking at a Stack Overflow table and guessing:
 * 		Which columns you'll join on
 * 		Which columns you'll filter on
 * 		Given that info, what should your indexes look like as a starting point?
 * 
 * 
 * Note to Brent: next points to think about:
 * 		Ordering after the joins (like sorting top comments by score desc)
 * 		Grouping by after the joins
 */
