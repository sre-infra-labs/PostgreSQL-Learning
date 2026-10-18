/* Fundamentals of Index Tuning
 * Module 1a: Which Columns Should We Index?
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

/* Start with no indexes on the users table.
 * The below script drops those indexes for you.
 * More info: https://smartpostgres.com/go/dropindexes 
 */
select * from drop_indexes('public', 'users');



/* When you create a table, which columns should you index?
 * 
 * To answer that, think about which columns you filter on.
 * The better you know your workload's queries, the easier it
 * is for you to just glance at a table's columns and say,
 * "We usually filter on columns A, B, and C."
 * 
 * One of the things I like about the Stack Overflow database
 * is that the tables are pretty easy to understand, and you
 * can probably guess which columns would be filtered on with
 * a typical web app like https://StackOverflow.com.
 * 
 * Take the users table for example - don't execute this, I'm
 * just showing you the structure:
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
/* You could glance down that list of columns and guess:
 * 
 * id: we're probably going to ask for users by their id a lot
 * 
 * reputation: we might run queries to find the highest-ranking
 * users, like sort by reputation descending. However, it'd be
 * really weird to say "show me all users with reputation = 12345."
 * 
 * creationdate: again, we might query for the most recently created
 * users, but ... we could just get that by id descending. We wouldn't
 * need to ask for specific creation date ranges.
 * 
 * By now, you're thinking, "Well, maybe we would? Maybe we'd have a
 * report that says, show me the number of people who signed up per
 * month." That's cool, but when you're just getting started putting
 * indexes on a table, don't index for maybe/someday - build indexes
 * to make the queries you use the most, run quickly. Later, you'll
 * see why adding too many indexes to a table can slow down inserts,
 * updates, and deletes.
 * 
 * The more you know your workload, the easier it is to glance at a
 * table and say, "These are the columns we filter on the most."
 * 
 * When you don't know your workload well, start by looking at
 * specific queries that are giving you performance problems.
 * 
 * We'll start with one.
 * 
 * 
 * 
 * Say I want to find the top Reputation users in a particular location, 
 * and show their web site so folks can go click on it and meet
 * interesting people: */
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl is not null
order by u.reputation desc
limit 100;



/* Uh oh - some websiteurls are blank, which means they're
 * populated with empty spaces. We'll need to filter differently: */
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> ''   /* was "is not null" */
order by u.reputation desc
limit 100;


/* Note that this query runs really quickly
 * because I'm using the small users table.
 * 
 * I'm sticking with the small table to explain concepts,
 * and because you're used to working with that table,
 * assuming that you've followed along with this class's
 * prerequisites, like Fundamentals of Select.
 * 
 * If a real-world query ran this quickly, you might not
 * even bother with indexes. But let's work on it in order
 * to learn concepts. 
 */



/* Get the explain plan and buffers: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> ''
order by u.reputation desc
limit 100;

/* Things to note: 
 * Where is Postgres getting the data from?
 * About how many buffers get read as-is? 
 * 		Scan: 2.6GB buffers
 * Is the query going parallel?
 */



/* It's tempting to say we either need an index on:
	location, websiteurl or
	websiteurl, location

But is just one column selective enough to help a lot?

Let's query the data to see how selective our filters are: */
select COUNT(*) from users where location = 'Helsinki, Finland';
select COUNT(*) from users where websiteurl <> '';
select count(*) from users;

/* for easier displaying: */
with users_in_helsinki as (select COUNT(*) as users_in_helsinki from users where location = 'Helsinki, Finland'),
users_with_websiteurl as (select COUNT(*) as users_with_websiteurl from users where websiteurl <> ''),
users_total as (select count(*) as users_total from users)
select users_in_helsinki, users_with_websiteurl, users_total
from users_in_helsinki, users_with_websiteurl, users_total;


/* For the query we're trying to tune: */
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> ''


/* Which one do we think Postgres will use between these two? */
create index users_location on users(location);
create index users_websiteurl on users(websiteurl);
  

/* Go ahead and start creating those while we discuss.
 * 
 * Databases will generally pick the index that help it
 * reduce the search space as quickly as possible, aka
 * which column's filters are more selective.
 * 
 * More selective = reduces search space a lot
 * Less selective = doesn't reduce the search space much
 *
 * Our filter on location = Helsinki is very selective,
 * because it reduces our search space to just 2,233 rows
 * out of 22 million.
 * 
 * Our filter on websiteurl <> '' is not as selective,
 * because even after applying that filter, we still have
 * 2.3 million rows that matched.
 * 
 * The filter on location is much more selective,
 * so Postgres will probably prefer an index on location
 * to quickly get to the 2233 rows that match our filter.
 * 
 * But let's test it out by creating both indexes, and
 * seeing which one Postgres prefers to use:
 */

/* Then run the query we're trying to tune again: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> ''
order by u.reputation desc
limit 100;

/* Things to note:
 * Where is Postgres getting the data from?
 * Is it using one index, or both?
 * About how many buffers get read as-is? 
 * Is the query going parallel?
 */





/* Postgres chose to use the index on location for these search filters: */
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> ''

/* If our query was different, and had different filters,
 * then that might change Postgres's decision.
 * 
 * For example, let's look for a specific websiteurl:
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl = 'http://lmgtfy.com'
order by u.reputation desc
limit 100;



/* Postgres uses BOTH indexes, finding:
 * 		The users who live in Helsinki
 * 		The users whose website is lmgtfy.com
 * And merges them together to pick out users who match
 * both filters! Cool.
 * 
 * Or, what if our location filter isn't that selective:
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'India'
  and u.websiteurl = 'http://lmgtfy.com'
order by u.reputation desc
limit 100;

/* Which index(es) did Postgres choose to use here?
 * Why? What is the selectivity of each filter?
 */




/* Takeaway:
 * 
 * Look at the columns you typically filter on in your where clauses.
 * 
 * Think about the values you look for (Helsinki, India, LMGTFY, etc)
 * and how selective they are.
 * 
 * If your query has selective searches on a column,
 * you probably want an index on that column.
 * 
 * If your query has multiple filters on multiple columns,
 * Postgres is smart enough to look at each filter
 * to figure out which one(s) are more selective,
 * and use indexes on those columns to do its filtering.
 * 
 * When you're just getting started indexing a table,
 * a good default strategy is to make a list of the columns
 * that you filter on, with selective filters, and create
 * single-column indexes on each of those.
 */
