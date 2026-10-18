/* Fundamentals of Index Tuning
 * Module 3 Lab: Designing Indexes for Order By
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

/* Start out with no indexes on users: */
select * from drop_indexes('public', 'users');



/* Task 1:
 * 
 * Design one index that will result in the least buffer reads
 * for the below query. Only write one create index statement.
 * You're allowed to run queries against the table for research
 * purposes, but you're only allowed to write one create index.
 * Try to get it right with just one shot.
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select *
from users u
where u.location = 'United States'
  and u.reputation > 10
order by u.lastaccessdate desc
limit 100;


/* To check your work, measure the number of buffer reads done
 * when the query uses your index.
 * 
 * Then, to test your work, try creating other indexes too.
 * Compare their reads to your index's reads, and see if any 
 * other indexes result in less buffer reads. You did a good
 * job if no other index combinations result in less reads.
 */







/* Task 2: same task, slightly different query: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select *
from users u
where u.location = 'Bologna, Italy'
  and u.reputation > 100
order by u.creationdate desc
limit 100;

/* And check your work the same way. */
