/* Fundamentals of Index Tuning
 * Module 4b: Designing Partial Indexes
 * 
 * 1.0 - 2025-04-07
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

/* Start by dropping all indexes on the users table: */
select * from drop_indexes('public', 'users');



/* Let's say we have a leaderboard query like this: */
select u.reputation, u.displayname, u.location, u.websiteurl, u.id
from users u
order by reputation desc
limit 100;




/* We want that query to run quickly, but we're constantly
 * inserting new users, so we can't afford to have an index
 * on reputation across our entire user base.
 * 
 * Create an index to make this query run quickly,
 * but the index is not allowed to contain all users rows,
 * especially not the tons of new users who constantly
 * sign up.
 * 
 * It's trickier than it looks!
 * 
 * You're allowed to change the query, but you're not allowed
 * to put in hard-coded date filters.
 * 
 * Good luck! Think out of the box.
 */
