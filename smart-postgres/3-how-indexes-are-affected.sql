/* Fundamentals of Vacuum
 * Module 3: How Indexes are Affected
 * 
 * v1.0 - 2024-10-25
 * https://smartpostgres.com/fundamentals/vacuum
 * 
 * This demo works on any version of Postgres,
 * and requires the free Stack Overflow database:
 * https://smartpostgres.com/go/getstack
 */



/* Recreate our 5M row users table,
 * but this time let's include a primary key
 * and indexes.
 * 
 * This must be done before class starts because
 * it takes a couple minutes due to the new indexes.
 */
drop table if exists users_demo;
CREATE TABLE users_demo (
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
	accountid int4 null,
	CONSTRAINT pk_users_demo__id PRIMARY KEY (id)
);
create index users_demo_location on users_demo(location);
create index users_demo_lastaccessdate on users_demo(lastaccessdate);
create index users_demo_reputation on users_demo(reputation);
create index users_demo_lastaccessdate_reputation
	on users_demo(lastaccessdate, reputation);

/* Just to control when vacuuming happens for the demo: */
ALTER TABLE users_demo SET (autovacuum_enabled = false);
/* In most cases, that's a bad idea (but not all).
 * I'm only doing it today so I can control when it happens.
*/


/* This is the slow part that takes about a minute: */
insert into users_demo
(id, reputation, creationdate, displayname, lastaccessdate, "location", "views", 
 upvotes, downvotes, emailhash, accountid)
	select id, reputation, creationdate, displayname, lastaccessdate, "location", "views", 
	 upvotes, downvotes, emailhash, accountid
		from public.users 
		where id >= 1
		order by id
		limit 5000000;


/* Check the sizes of the objects, and copy/paste them here: */
select * from check_indexes('public', 'users_demo');

/* Sizes:
pk_users_demo__id						109696
users_demo_lastaccessdate				141504
users_demo_lastaccessdate_reputation	198336
users_demo_location						 38808
users_demo_reputation					 34648
ordinary table							463960
 */


/* Simulate 10% of folks logging in, takes ~15 seconds */
update public.users_demo
	set lastaccessdate = now()
	where id % 10 = 0; /* only where the id is evenly divisible by 10,
							so approx 10% of the rows */

/* How big is our table now? */
select * from check_indexes('public', 'users_demo');
	


/* It makes sense that the base table (aka the white pages)
 * grows because we're making new versions of the rows.
 * 
 * It makes sense why indexes on lastaccessdate (aka the black pages)
 * grow because people are logging in NOW, which would be
 * the very tail end of the index.
 * 
 * We're allocating new pages for that index, to pick people
 * up from their old lastaccessdate and move them to now.
 * 
 * On the black pages, the space where their old lastaccessdate was
 * is now unused. That space will never get reused as-is because
 * no one is going to log in in the past, with that old lastaccessdate.
 * 
 * We're gonna need to reclaim that space eventually.
 * 
 * 
 * But also, check out the indexes on location and reputation!
 * They also grew! Why? They don't have lastaccessdate on 'em, do they?
 * 
 * Here's what the index on reputation holds, for example:
 */
select reputation, ctid
	from users u 
	order by reputation 
	limit 100;


/* In order to join between the index (black pages) and the heap (white pages),
 * Postgres puts the ctid on the index.
 * 
 * And after we updated folks' lastaccessdate, their ctid changed.
 * 
 * We moved their row on the white pages.
 * 
 * So the indexes have to change as well.
 * 
 * As Biggie Smalls notoriously sang, "More indexes, more problems."
 * Indexes can make select queries go faster, but they also slow down
 * inserts, updates, and deletes, and they get bloated and require
 * maintenance.
 */


/* As the table contents continue to change,
 * the table AND its indexes will grow larger.
 * This takes about another 45 seconds: */
update users_demo
	set lastaccessdate = now()
	where id % 3 = 0 /* A bigger chunk of the table, about 1/3 */



/* How big is our table now, compared to its original size
 * (scroll up in the comments to see our original size) */
select * from check_indexes('public', 'users_demo');




/* In the last module, I showed you how heap scans will take longer.
 * We did a count(*) across the heap, and the more changes our table had,
 * the more buffers we had to read.
 * 
 * But now that we have indexes, queries can go faster.
 * Will queries with indexes be affected by the larger size
 * of the tables & indexes, and the dead space they hold?
 * 
 * 
 * If I want to find my local friends:
 */
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select *
	from users_demo
	where location = 'Las Vegas, NV, US';

/* We only hit 3 buffers, which is pretty damn fast.
 * 
 * We open the location index and divebomb into
 * Las Vegas, and then read out all of the rows.
 * 
 * Because there are relatively few people in Vegas
 * (think thousands, not millions)
 * then even if fully half of the space is old
 * versions of rows, it's not really a problem.
 * 
 * Vegas residents fit on so few pages it doesn't matter.
 * 
 * But the more rows our query wants to read from the index,
 * the more pages it's going to have to read,
 * and the higher likelihood that we're going to
 * find a lot of dead rows, meaning longer queries.
 * 
 * Let's use a more popular location,
 * and run this a couple of times:
 */
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select *
	from users_demo
	where location = 'India';

/* COPY THE PERFORMANCE METRICS HERE:

Bitmap Heap Scan on public.users_demo  (cost=251.48..20199.87 rows=6588 width=438) (actual time=6.778..124.371 rows=28481 loops=1)
  Output: id, reputation, creationdate, displayname, lastaccessdate, location, views, upvotes, downvotes, emailhash, accountid
  Recheck Cond: ((users_demo.location)::text = 'India'::text)
  Heap Blocks: exact=27968
  Buffers: shared hit=3 read=28021 written=14701
  ->  Bitmap Index Scan on users_demo_location  (cost=0.00..249.84 rows=6588 width=0) (actual time=3.917..3.917 rows=40664 loops=1)
        Index Cond: ((users_demo.location)::text = 'India'::text)
        Buffers: shared hit=3 read=53
 */



/* To fix these problems, we can do a vacuum full,
 * but the more copies of the table we have (indexes),
 * the longer vacuum full will take:
 */
vacuum full users_demo;

/* This takes a long time because it has to do all this:
 * 
 * Build a new heap (aka white pages), with new ctids for each row
 * 
 * Build a new copy of each index, with each index pointing to
 * 		the new ctid for each row, and it also makes the index
 * 		smaller at that same time because it's only including
 * 		the current version of each row
 */


/* And then try India again: */
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select *
	from users_demo
	where location = 'India';

/* And compare the blocks & buffers. */


/* While that runs, recap:
 * 
 * When we update contents of an ordinary table,
 * 		we have to make a new copy of the row
 * 		for versioning, so its row size doubles.
 * 
 * When we update contents of an INDEX,
 * 		we're usually moving its contents from
 * 		one place in the index to another,
 * 		like changing LastAccessDate from
 * 		yesterday to today. That increases the
 * 		index's size because the old space can't
 * 		be compacted right away, and that old space
 * 		(for LastAccessDate) will never be used.
 * 		For other index contents, like say Location
 * 		or DisplayName, it might get reused.
 * 		Someone might move out of Las Vegas,
 * 		leaving space, but then someone else might
 * 		move in.
 * 
 * The bigger the index becomes, that makes the
 * 		database larger, and it affects scan speed
 * 		when we need to read large ranges of rows.
 * 
 * However, if we're only reading a handful of rows,
 * 		dead empty space isn't really a concern.
 * 
 * The more indexes you have,
 * the more important vacuuming becomes,
 * and yet, the slower it becomes.
 * 
 * We're going to need to nibble it off in smaller
 * chunks, perhaps automatically. We'll cover that next.
*/
