/* Fundamentals of Vacuum
 * Module 4: How Autovacuum Tries to Handle It
 * 
 * v1.0 - 2024-10-25
 * https://smartpostgres.com/fundamentals/vacuum
 * 
 * This demo works on any version of Postgres,
 * and requires the free Stack Overflow database:
 * https://smartpostgres.com/go/getstack
 */

set search_path to public;

/* Recreate our 5M row users table with indexes,
 * but this time leave autovacuum on.
 * 
 * This must be done before class starts because
 * it takes several minutes due to the new indexes.
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




/* Now that we've got autovacuum on,
 * simulate 10% of folks logging in, takes ~15 seconds */
update public.users_demo
	set lastaccessdate = now()
	where id % 10 = 0;

/* Right away, check the sizes compared to before: */
select * from check_indexes('public', 'users_demo');
	



/* Simulate 1/3 of folks logging in, takes ~45 seconds */
update public.users_demo
	set lastaccessdate = now()
	where id % 3 = 0;

/* Right away, check the sizes compared to before: */
select * from check_indexes('public', 'users_demo');

/* The indexes still grow. We need to keep versions in the db.
 * 
 * Review:
 * size_kb compared to before
 * estimated_tuples
 * estimated_tuples_as_of
 * dead_tuples
 * last_autovacuum
 *
 *
 *
 * Wait a minute or two, and re-check size_kb, dead_tuples,
 * and the warnings.
 * 
 * Eventually, autovacuum kicks in.
 * 
 * But what happened? We didn't get a VACUUM FULL,
 * a brand new copy of the table & indexes.
 * 
 * We got a plain old VACUUM, which among other things:
 * 
 * 		Notes which row versions no longer need to be kept around.
 * 
 * 		Changes dead tuples (row versions) to reusable space.
 * 
 * 		Does not shrink the number of 8KB pages: just makes space
 * 			available inside those pages.
 * 
 * 		Updates statistics used by the planner, like estimated_tuples.
 * 
 * This is done automatically by Postgres in the background
 * in a process called autovacuum.
 * 
 * 
 * We can watch autovacuum as it runs. First, modify a lot of data:
 * This takes about another 45 seconds: */
update users_demo
	set lastaccessdate = now()
	where id % 3 = 0 /* A bigger chunk of the table, about 1/3 */


/* And then query check_indexes repeatedly: */
select *
	from check_indexes('public', 'users_demo');
	




 /* If any table's individual autovacuum settings have been changed,
 * we surface that in the warnings column in check_indexes.
 * Otherwise, tables inherit the database-wide settings that
 * are visible in pg_settings:
 */
select *
	from pg_catalog.pg_settings ps 
	where name like 'autovacuum%'
	order by name;




/* In many cases, autovacuum is all the maintenance we need! It:
 * 
 * 		Frees up space inside pages
 * 
 * 		Get the planner stats up to date
 * 
 * But there are still two problems:
 * 		
 * 		The heap is larger than it should be
 * 			(although that space can be reused)
 * 
 * 		Indexes like lastaccessdate is larger than it should be
 * 			(and that space will NOT be reused, since people
 * 			don't log in in the past. Similar problems will
 * 			pop up on any ascending key.)
 * 
 * So we're going to need a mix:
 * 
 * 		Good autovacuum settings for live maintenance 24/7
 * 
 * 		Periodic manual vacuum fulls to handle outliers
 * 
 * 		And we need to know when autovacuum can't keep up
 */
