/* Fundamentals of Vacuum
 * Module 2: Unvacuumed Tables are Bigger and Slower
 * 
 * v1.0 - 2024-10-25
 * https://smartpostgres.com/fundamentals/vacuum
 * 
 * This demo works on any version of Postgres,
 * and requires the free Stack Overflow database:
 * https://smartpostgres.com/go/getstack
 * 
 */



/* In the last module, we made a small subset of the users table.
 * 
 * Let's switch to the real StackOverflow.com users table,
 * although I'm not going to use all of the columns or indexes yet: */

drop table if exists users_demo;
create table users_demo (
	id int4 NOT NULL,
	reputation int4 NULL,
	creationdate timestamp NULL,
	displayname varchar(40) NULL,
	lastaccessdate timestamp NULL,
	"location" varchar(100) NULL,
	"views" int4 NULL,
	upvotes int4 NULL,
	downvotes int4 NULL,
	emailhash varchar(32) NULL,
	accountid int4 NULL
);
/* Just to control when vacuuming happens for the demo: */
alter table users_demo SET (autovacuum_enabled = false);


/* Load it with 5M rows, takes ~15 seconds: */
insert into users_demo
(id, reputation, creationdate, displayname, lastaccessdate, "location", "views", 
 upvotes, downvotes, emailhash, accountid)
select id, reputation, creationdate, displayname, lastaccessdate, "location", "views", 
 upvotes, downvotes, emailhash, accountid
from public.users 
where id >= 1
order by id
limit 5000000;



/* The table is about 500MB in size, 464MB to be kinda exact: */
select * from check_indexes('public', 'users_demo');


/* The first rows in the table start at page 0, tuple 1: */
select ctid, xmin, xmax, *
from users_demo u 
order by id
limit 100;



/* We're going to update about 10% of the rows.
 * To do that, let's pick everyone whose id is evenly
 * divisible by 10:
 */
select *
	from public.users_demo ud 
	where id % 10 = 0		/* only where the id is evenly divisible by 10,
	order by id					so approx 10% of the rows */
	limit 100;


/* Simulate 10% of folks logging in, takes about 10 seconds: */
update public.users_demo
	set lastaccessdate = now()
	where id % 10 = 0; 

/* How big is our table now? */
select * from check_indexes('public', 'users_demo');
	

/* Note the new ctids for rows ending in 0, like id 10, 20, 30: */
select ctid, xmin, xmax, *
	from users_demo u 
	order by id
	limit 100;

/* When Postgres needed to make a new version of row 10,
 * Sneakers O'Toole, because his lastaccessdate changed,
 * there was no space left on page 0 to do it.
 * 
 * The new version of Sneakers (id 10) is on a much
 * higher page number. And so is id 20, 30, 40, etc.
 * 
 * The old version of Sneakers (id 10) on page 0 will
 * be useless, aka dead to us, as transactions move on.
 * No one will need to read that old dead version of
 * the row because the new version is committed.
 * 
 * ctid(0,8) - Sneakers id 10, v1 - is dead to us.
 * 
 * That's called a dead tuple.
 */



/* If you look at your 8KB pages, you can imagine that
 * over time, they'll have more and more dead tuples
 * on them, and that's just wasted space.
 * 
 * Can we reuse the space from those dead tuples
 * when we do inserts? Let's find out:
 */

/* Insert 10 new rows, and use really high ids
 * just so we can find them quickly in the table:
 */
insert into users_demo
(id, reputation, creationdate, displayname, lastaccessdate, "location", "views", 
 upvotes, downvotes, emailhash, accountid)
	select 20000000 + id, reputation, creationdate, displayname, lastaccessdate, "location", "views", 
	 upvotes, downvotes, emailhash, accountid
		from public.users
		where id >= 1
		order by id
		limit 10;


/* Where did they end up?
 * Did Postgres reuse the space from the dead tuples
 * on page 0? */
select ctid, xmin, xmax, *
	from users_demo u 
	order by id desc
	limit 100;


/* No: the rows were added to higher pages,
 * indicating that the dead tuples are still
 * hanging around on page 0, taking up space.
 */


/* Note the size of our table now: */
select * from check_indexes('public', 'users_demo');


/* As the table contents continue to change,
 * the table will grow larger. ~15 seconds: */
update users_demo
	set lastaccessdate = now()
	where id % 3 = 0 /* A bigger chunk of the table, about 1/3 */



/* How big is our table now? */
select * from check_indexes('public', 'users_demo');
	

/* Over time, the table grows larger.
 * 
 * The larger our table becomes, the slower our selects
 * may also become, because they have to read more pages.
 * 
 * Let's see the current bloated size cost.
 * 
 * Run this query 2-3 times because if you only run it once,
 * the comparison will be unfair:
 */
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select COUNT(*) from users_demo;

/* COPY THE PERFORMANCE METRICS BELOW:


Finalize Aggregate  (cost=85375.26..85375.27 rows=1 width=8) (actual time=219.961..221.373 rows=1 loops=1)
  Output: count(*)
  Buffers: shared hit=16211 read=61301
  ->  Gather  (cost=85375.04..85375.25 rows=2 width=8) (actual time=219.547..221.367 rows=3 loops=1)
        Output: (PARTIAL count(*))
        Workers Planned: 2
        Workers Launched: 2
        Buffers: shared hit=16211 read=61301
*
* Then vacuum the table to clean out the old dead tuples.
* While it runs, discuss what's happening under the hood
* as vacuum runs, building a full new copy of the table:
*/
vacuum full users_demo;


/* Run the select again and note its new performance metrics: */
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select COUNT(*) from users_demo;

/* The number of buffers read is down quite a bit
 * because the table is physically smaller again: */

select * from check_indexes('public', 'users_demo');


/* It's smaller because vacuum built a brand new copy
 * of the table, starting from page 0. Prove it: */
select ctid, xmin, xmax, *
from users_demo u 
order by id
limit 100;

/* Note that the rows aren't in order.
 * When Postgres built a new table,
 * it found ids 10, 20, 30, etc later in the source copy,
 * so they end up later in the new copy coincidentally.
 * 
 * If we want to see the rows on the first page: */

select ctid, xmin, xmax, *
from users_demo u 
order by ctid
limit 100;


/* If we want the table sorted by something,
 * it's up to us to specify that with the CLUSTER command:
 * https://www.postgresql.org/docs/current/sql-cluster.html
 * 
 * But that does require an index on the table.
 * Right now, we don't have an index, and we'll
 * discuss that in the next module.
 */



/* So to recap:
 * 
 * Inserts and updates cause the ordinary table to grow.
 * 
 * The growth affects the table size, AND query duration.
 * 
 * Vacuuming builds a brand new copy of the table,
 * 		fixing the size & query duration problems.
 * 
 * The new copy isn't sorted - it just takes up less
 * 		space and gets faster queries.
*/
