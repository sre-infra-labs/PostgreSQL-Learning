/* Fundamentals of Index Tuning
 * Module 2a: Why Timestamp Columns Often Need Functional Indexes
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


/* start with no indexes: */
select * from drop_indexes('public', 'users');

/* For dates & times, we almost never use equality searches.
 * 
 * You wouldn't write this: */

select *
from users
where creationdate = '2008-08-07 11:24:18.960';




/* Instead, we usually look for date ranges like this: */

select *
from users
where creationdate >= '2008-08-07'
  and creationdate < '2008-08-08'
order by creationdate;

/* Whether you're doing an equality search like =,
 * or a range search like >= and <,
 * this index will help:
 */
create index users_creationdate on users(creationdate);

/* Check out the query plan to see if our index was used: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select *
from users
where creationdate >= '2008-08-07'
  and creationdate < '2008-08-08'
order by creationdate;


/* Another way to get all the users for a specific day: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select *
from users
where creationdate::date = '2008-08-07'::date
order by creationdate;


/* That query is logically identical,
 * and produces the same rows,
 * but Postgres doesn't build the same plan.
 * 
 * That query is not sargable.
 * The query's Search ARGuments (SARG) are not written in a way
 * that Postgres can dive into a single area of the index.
 * 
 * Instead, it scans the ENTIRE index.
 * 
 * There's no reason that Postgres couldn't rewrite this: */

where creationdate::date = '2008-08-07'::date

/* Into this: */

where creationdate >= '2008-08-07'
  and creationdate < '2008-08-08'

/* But it just doesn't.
 * 
 * Postgres IS open source, so in theory, YOU could submit a
 * pull request to Postgres to make that magic happen. I'd
 * love to see it. But until you get up off your lazy rear,
 * we're going to have to either rewrite our queries to be
 * sargable (and we both know that's not gonna happen) or
 * we're going to need to store our data in a different way.
 * 
 * Here's another example of a query that technically works,
 * but Postgres doesn't build a fast query plan for it using our index:
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS)
select *
from users
where date_trunc('day', creationdate) = '2008-08-07'::timestamp
order by creationdate;


/* Yet another non-performant idea: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS)
select *
from users
WHERE EXTRACT(YEAR FROM creationdate) = 2008
  AND EXTRACT(MONTH FROM creationdate) = 8
  AND EXTRACT(DAY FROM creationdate) = 7
order by creationdate;


/* And please don't ever do this, either: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS)
select *
from users
  WHERE to_char(creationdate, 'YYYY-MM-DD') = '2008-08-07'
order by creationdate;


/* If your queries are concise and clear, like this: */
where creationdate >= '2008-08-07'
  and creationdate < '2008-08-08'

/* then your indexes can be concise and clear too, like this: */
create index users_creationdate on users(creationdate);

/* But if they're not, we're going to need another kind of index:
 * functional indexes.
 * 
 * Let's say all our date-based queries look like this,
 * and we can't change them:
 */
select *
from users
where creationdate::date = '2008-08-07'::date
order by creationdate;


/* if we want this to run quickly, we need to pre-calculate
 * creationdate::date
 * 
 * and store it in a way that we can seek on it.
*/
create index users_creationdate_as_date on users((creationdate::date));

/* Rerun our non-sargable query: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select *
from users
where creationdate::date = '2008-08-07'::date
order by creationdate;


/* The good news: our query runs fast without changes.
 * Suddenly our query is sargable without having to rewrite it!
 * 
 * The bad news: now we have 2 indexes on the same column.
 * The more indexes we have (on any columns), that causes:
 * 		Slower inserts/updates/deletes
 * 		Larger database size
 */
select index_name, index_type, index_definition, size_kb 
from check_indexes('public', 'users')
where index_type <> 'toast';




/* Takeaways:
 * 
 * If all your queries ALL use the concise and clear method
 * of passing in dates & times, and you're not running
 * any functions on the contents of the table,
 * then you can get by with a regular index on the timestamp column.
 * 
 * If your queries ALL use some other method,
 * like creationdate::date,
 * and they ALL use exactly the same method,
 * then a single functional index that matches your query's function.
 * 
 * If your queries use a hot mess of different methods,
 * then you have to make some tough choices, because
 * if you create functional indexes for all the different methods,
 * then your inserts/updates/deletes will be slow as Postgres
 * has to maintain all those different copies of the data.
 */
