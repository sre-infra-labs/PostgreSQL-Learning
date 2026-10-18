/* Fundamentals of Index Tuning
 * Module 1 Lab: Which Columns Should We Index?
 * 
 * v1.0 - 2025-04-07
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


/* Start with no indexes: */
select * from drop_indexes('public', 'users');
select * from drop_indexes('public', 'comments');

/* Review the structure of the users table and think about:
 * 
 * 		A. Which columns will likely show up in where clauses?
 * 
 * 		B. Are their contents selective? Will the where clause
 * 		   on this column make your search space smaller?
 * 
 * You can either look at the table's definition in your
 * database tool (like DBeaver, Datagrip, PGadmin, etc)
 * or script out the table definition like this:
*/

CREATE TABLE public.users (
	id int4 NOT NULL,
	reputation int4 NULL,
	creationdate timestamp NULL,
	displayname varchar(40) NULL,
	lastaccessdate timestamp NULL,
	websiteurl varchar(200) NULL,
	"location" varchar(100) NULL,
	aboutme text NULL,
	"views" int4 NULL,
	upvotes int4 NULL,
	downvotes int4 NULL,
	profileimageurl varchar(200) NULL,
	emailhash varchar(32) NULL,
	accountid int4 NULL,
	CONSTRAINT pk_users__id PRIMARY KEY (id)
);

/* Task #1:
 * 
 * After doing A/B above, create a set of starter indexes
 * that you think will help most queries run faster.
 * Script out your index designs below: 
 */












/* Task #2:
 * 
 * Run each of the following queries and review their plans.
 * Find out if the queries use your newly-created indexes,
 * or if they're doing heap scans.
 * 
 * If you did a good job on task #1, all of the below queries
 * will use your indexes.
 * 
 * If any of them do heap scans, can you design an index that
 * will help them read less data?
*/

/* People who live in a specific location: */
select u.reputation, u.id, u.displayname, u.location, u.websiteurl
from users u
where u.location = 'Las Vegas, NV'
order by u.reputation desc 
limit 100;

/* If the system lets people log in by display name, we might run: */
select *
from users u
where u.displayname = 'Brent Ozar';

/* Find high-ranking people who haven't accessed the system lately: */
select u.lastaccessdate, u.reputation, u.id, u.displayname, u.location
from users u
where reputation > 10000
  and lastaccessdate < '2023-01-01'::date
order by lastaccessdate
limit 100;


/* When reviewing your work, if you discover that you created
 * too MANY indexes, and a lot of them weren't used by the
 * above queries, that's okay!
 * 
 * I only gave you a few queries here to keep your lab time short.
 * Real-world applications would of course have more than 4 queries.
 * 
 * For now, I'm not worried about you creating too many indexes.
 * We'll discuss the problems with that later.
 */






/* Task #3:
 * 
 * Let's do the same thing again, but with a different table.
 * 
 * Review the structure of the comments table and think about:
 * 
 * 		A. Which columns will likely show up in where clauses?
 * 
 * 		B. Are their contents selective? Will the where clause
 * 		   on this column make your search space smaller?
 * 
 * You can either look at the table's definition in your
 * database tool (like DBeaver, Datagrip, PGadmin, etc)
 * or script out the table definition. This time, I'm not doing
 * it for you.
 * 
 * After doing 1/2/3 above, create a set of starter indexes
 * that you think will help most queries run faster.
 * Script out your index designs below: 
*/







/* Task #4:
 * 
 * Run each of the following queries and review their plans.
 * Find out if the queries use your newly-created indexes,
 * or if they're doing heap scans.
 * 
 * If you did a good job on task #3, all of the below queries
 * will use your indexes.
 * 
 * If any of them do heap scans, can you design an index that
 * will help them read less data?
*/


/* Find all the comments for a single post: */
select c.userdisplayname, c.text, c.score, c.id
from comments c
where c.postid = 2315087
order by creationdate;


/* Find the most popular comments I've left: */
select c.id, c.score, c.text
from comments c
where c.userid = 26837
order by score desc
limit 100;



/* I'm only giving you 2 queries here, and believe it or not,
 * that's pretty much all the kinds of queries that would
 * normally be run on a table like this.
 * 
 * There may be other one-off analytical queries, perhaps
 * like if we're looking for obscenity in comments, like this:
 */

select *
from comments c
where c.text like '%cobol%'
limit 100;

/* But you wouldn't normally index for one-off queries like that,
 * because analytical queries are kinda allowed to run more
 * slowly. If someone needs sub-second response times for one-off
 * analytical queries, that's a different story, and not something
 * that I'd cover in Fundamentals of Index Tuning.
 * 
 * (Also, I'm joking about cobol being a dirty word. (Kinda.))
 */