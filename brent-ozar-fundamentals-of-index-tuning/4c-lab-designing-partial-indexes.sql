/* Fundamentals of Index Tuning
 * Module 4c: Designing Partial Indexes
 * 
 * 1.0 - 2025-04-07
 * https://smartpostgres.com/fundamentals/index-tuning
 * 
 * This demo works on any version of Postgres,
 * but requires the large posts table:
 * https://smartpostgres.com/go/querystack
 * 
 * Licensed under Creative Commons CC BY-SA 4.0
 * Attribution-ShareAlike 4.0 International:
 * https://creativecommons.org/licenses/by-sa/4.0/
 */


/* Up til now, all of our work has been on the relatively small
 * users table.
 * 
 * This is your first module that involves a much larger table.
 * 
 * Performance issues will be much more obvious here,
 * and creating indexes will also take much longer here.
 * 
 * If you have the hardware & space where you can do this, great!
 * Follow along and you'll learn valuable lessons.
 * 
 * If not, no worries, just watch the video where I show you how
 * I do the lab exercise.
 */




/* Start by dropping all indexes on the posts table: */
select * from drop_indexes('public', 'posts');


/* StackOverflow.com is a question & answer site.
 * 
 * In the posts table, they store both questions AND answers
 * (and some other stuff too.)
 * 
 * The posttypeid column tells you what kind of data it is:
 * 	1 = question
 *  2 = answer
 * 
 * When we're searching for QUESTIONS, our queries look like this:
 */
select *
from posts p
where p.posttypeid = 1
  and p.tags = '<postgresql>'
order by score desc
limit 100; 


/* When we're searching for ANSWERS, we never look at tags.
 * (In fact, if posttypeid = 2, the tags column will be null.)
 * 
 * Instead, when we search for answers, we're almost always looking
 * for the answers to one specific question. Answers have a parentid
 * column, and that id matches up to the question's id.
 * 
 * For example, take this page showing a question and its answers:
 * https://stackoverflow.com/questions/7395915/
 * 
 * To see those answers, we would query:
 */
select *
from posts p
where p.parentid = 7395915
  and p.posttypeid = 2
order by p.score desc;



/* So we need to build an indexing strategy for the posts table,
 * knowing that we have two styles of querying:
 */
where parentid = some number, and posttypeid = 2

or

where tags = some value, and posttypeid = 1


/* Task 1:
 * 
 * Build indexes to suit this use case, but keep each index's
 * physical size as small as possible, because this table is big.
*/




/* Task 2:
 * 
 * After you've built your indexes, run these queries and make
 * sure they use your newly-created indexes, and run quickly:
 */
select *
from posts p
where p.posttypeid = 1
  and p.tags = '<postgresql>'
order by score desc
limit 100; 

select *
from posts p
where p.parentid = 7395915
  and p.posttypeid = 2
order by p.score desc;



