/* Fundamentals of Index Tuning
 * Module 2 Lab: Designing Indexes for Timestamp Columns
 * 
 * v1.0 - 2025-04-07
 * https://smartpostgres.com/fundamentals/index-tuning
 * 
 * This demo works on any version of Postgres,
 * but requires the large comments table:
 * https://smartpostgres.com/go/querystack
 * 
 * Licensed under Creative Commons CC BY-SA 4.0
 * Attribution-ShareAlike 4.0 International:
 * https://creativecommons.org/licenses/by-sa/4.0/
 */


/* We've been working a lot with the users table because
 * it's small and easy to understand.
 * 
 * For this exercise, we're going to move up to the comments
 * table because it has a lot more rows, so slow queries
 * will be a lot more noticeably slower.
 * 
 * Check out the structure of the comments table, and note
 * that it has a creationdate timestamp column.
 */

/* Is there already an index on creationdate? */
select * from check_indexes('public', 'comments');

/* If not, add one: */
create index comments_creationdate on comments(creationdate);





/* Task 1:
 * 
 * Write 3 different queries searching for short ranges
 * of creation dates (like an hour, a day, or a week)
 * using 3 different techniques.
 * 
 * Your queries' where clauses should look different,
 * not all exactly the same with just different ranges.
 * 
 */






/* Task 2:
 * 
 * Test your queries to see if they used the "normal"
 * index on creationdate.
 * 
 * If they all do, then don't get too excited. It means
 * you probably didn't succeed at task #1. All of your
 * queries probably have similar where clauses, and you
 * need to get more creative.
 * 
 * If some of your queries do NOT use the index on
 * creationdate, that's actually great! That means you
 * were creative, just like our real world users and
 * developers are.
 * 
 * So your task #2 is to create indexes that will support
 * your creative queries.
 * 
 * You'll know you've succeeded when you review your queries'
 * explain plans, look at the buffers read, and:
 * 
 * 		The amount of data read is smaller than the entire heap
 * 
 * 		And the amount of data read is smaller than the
 * 		entire date index you created (meaning, we're diving
 * 		into specific date ranges rather than scanning the
 * 		entire index and checking every date.)
 */
