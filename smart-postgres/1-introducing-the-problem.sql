/* Fundamentals of Vacuum
 * Module 1: Introducing the Problem
 * 
 * v1.0 - 2024-10-25
 * https://smartpostgres.com/fundamentals/vacuum
 * 
 * This demo works on any version of Postgres.
 */

select version();



/* Create a simple table like the Stack Overflow users table,
 * but a simplified version for now:
 */
drop table if exists public.users_mini;

CREATE TABLE public.users_mini (
	id int4 NOT NULL,
	displayname varchar(40) NULL,
	reputation int4 NULL,
	lastaccessdate timestamp NULL,
	filler varchar null
);

/* Turn off autovacuum for now, will explain more on that in another session: */
ALTER TABLE users_mini SET (autovacuum_enabled = false);


/* Load the table, including some filler to make the rows bigger: */
insert into public.users_mini
	(id, displayname, reputation, lastaccessdate, filler)
values
	(1, 'Alex', 1, '2024-10-07 06:32', repeat('x', 750)),
	(2, 'Billie', 1, '2024-10-07 06:32', repeat('x', 750)),
	(3, 'Charlie', 1, '2024-10-07 06:32', repeat('x', 750)),
	(4, 'Deven', 1, '2024-10-07 06:32', repeat('x', 750)),
	(5, 'Eli', 1, '2024-10-07 06:32', repeat('x', 750)),
	(6, 'Flynn', 1, '2024-10-07 06:32', repeat('x', 750)),
	(7, 'Grey', 1, '2024-10-07 06:32', repeat('x', 750)),
	(8, 'Harper', 1, '2024-10-07 06:32', repeat('x', 750)),
	(9, 'Ishana', 1, '2024-10-07 06:32', repeat('x', 750)),
	(10, 'Jayden', 1, '2024-10-07 06:32', repeat('x', 750)),
	(11, 'Kai', 1, '2024-10-07 06:32', repeat('x', 750)),
	(12, 'Luka', 1, '2024-10-07 06:32', repeat('x', 750)),
	(13, 'Maverick', 1, '2024-10-07 06:32', repeat('x', 750)),
	(14, 'Noah', 1, '2024-10-07 06:32', repeat('x', 750)),
	(15, 'Ormonde', 1, '2024-10-07 06:32', repeat('x', 750)),
	(16, 'Parker', 1, '2024-10-07 06:32', repeat('x', 750)),
	(17, 'Quinn', 1, '2024-10-07 06:32', repeat('x', 750)),
	(18, 'Riley', 1, '2024-10-07 06:32', repeat('x', 750)),
	(19, 'Saarik', 1, '2024-10-07 06:32', repeat('x', 750)),
	(20, 'Taylor', 1, '2024-10-07 06:32', repeat('x', 750)),
	(21, 'Ushi', 1, '2024-10-07 06:32', repeat('x', 750)),
	(22, 'Val', 1, '2024-10-07 06:32', repeat('x', 750)),
	(23, 'Wyatt', 1, '2024-10-07 06:32', repeat('x', 750)),
	(24, 'Xiao', 1, '2024-10-07 06:32', repeat('x', 750)),
	(25, 'Ying', 1, '2024-10-07 06:32', repeat('x', 750)),
	(26, 'Zoe', 1, '2024-10-07 06:32', repeat('x', 750));


/* What does our table look like? */
select ctid, xmin, xmax, * from public.users_mini order by id;


/* Columns:
 * ctid: Postgres's tuple identifier.
 * 		First number: page number of this table, starting at 0.
 * 		Second number: tuple number of this row, starting at 1.
 * 
 * xmin & xmax: we'll cover this in another module.
 * 
 * filler: Just to get each row to take up more space,
 * 		so that just these 26 rows will take up multiple pages.
 * 
 * The table has 3 pages in right now.
 * 
 * We use the printed 8kb pages in Fundamentals of Select
 * (and in this class, and in more) because it helps illustrate
 * what the ctid is for.
 */


/* Check the object size, and note that it's 24kb,
 * because 3 pages * 8kb each = 24kb: */
select * from check_indexes('public', 'users_mini');


/* As our data changes - like let's say everyone just logged in: */
update public.users_mini
	set lastaccessdate = now();

/* Postgres keeps old copies of the rows inside the table,
 * so look at where our rows live now: */
t
/* id 1, Alex, used to be ctid (0,1), indicating that they
 * were the first row on the first page.
 * 
 * Now, the current version of Alex's row is higher,
 * indicating that they moved.
 */


/* Check the size again, and it's increased: */
select * from check_indexes('public', 'users_mini');

/* Postgres keeps multiple versions of rows inside the table
 * in order to improve concurrency.
 * 
 * Multi-Version Concurrency Control (MVCC)
 * 
 * Other databases call this:
 * Read Committed Snapshot Isolation (RCSI)
 * 
 * When you change a row, Postgres keeps the old version
 * of the row inside the table so readers can access it
 * even when your write transaction is still open.
 * 
 * That's a good thing, because Postgres has less blocking
 * and deadlocking by default than other databases that
 * don't default to MVCC/RCSI.
 * 
 * The xmin & xmax columns are used to help the engine
 * figure out which version of a row a query should see.
 * 
 * 
 * The good news: queries go faster with less blocking.
 * 
 * The bad news: our table is getting larger, and we're
 * going to have to clean out those old versions of rows
 * at some point.
 * 
 * One way to do that is to make a new copy of the table,
 * with none of the old versions in it. Postgres calls that
 * vacuum full.
 */

/* Before doing a vacuum full, note where the rows live: */
select ctid, xmin, xmax, * from public.users_mini order by id;

/* Make a new copy of the table, vacuuming out the dead versions: */
vacuum full public.users_mini;


/* Now, id 1 Alex lives on the first page again: */
select ctid, xmin, xmax, * from public.users_mini order by id;

/* And the table's size is back down to its original 24kb,
 * which is all that's needed to hold these rows: */
select * from check_indexes('public', 'users_mini');


/* At first, frequent vacuum fulls might sound like a good idea,
 * but there are downsides:
 * 
 * Vacuum full exclusively locks the table while it runs.
 * 
 * Vacuum full reads the whole table, and writes it all back out.
 * 
 * This generates a lot of storage activity, which can cause
 * problems for high availability & disaster recovery setups,
 * because the replicas may have to do the same write activity.
 * 
 * 
 * 
 * 
 * To avoid that, Postgres has a background activity
 * that's LIKE vacuum full, but different.
 * 
 * It's called autovacuum, and readers with the eyes of eagles
 * and the memory of elephants may remember that I turned it off
 * for this table at the beginning of this demo:
 */
alter table users_mini set (autovacuum_enabled = false);


/* In real life, you almost never wanna disable autovacuum
 * either server-wide or at the table level.
 * 
 * I'm only doing it here so that autovacuum doesn't kick off
 * while I'm explaining something to you onscreen. I need the
 * tables to remain in a consistent state while I dazzle you
 * with my jazz hands.
 * 
 * 
 * 
 * 
 * Now that you've learned the basics:
 * 
 * 		Postgres keeps old row versions around in the table
 * 
 * 		Vacuum full builds a new, smaller copy of the table
 * 			with no old versions in it
 * 
 * 
 * Now I'm going to switch to a much larger table because:
 * 
 * 		Autovacuum settings for tiny tables will be deceiving
 * 
 * 		I need to show dead tuple overhead, but that would
 * 			be hard on a really tiny table
 * 
 * 		I need to show autovacuum running live, which is
 * 			nearly instantaneous on tiny tables
 * 
 * 
 * So in the next module, we'll switch to a bigger users table.
 */


