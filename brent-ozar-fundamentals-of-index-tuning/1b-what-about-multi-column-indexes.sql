/* Fundamentals of Index Tuning
 * Module 1b: What If We Used Multi-Column Indexes?
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

/* In the last module, we settled on these two single-column
 * indexes to make our query go faster. If you don't have
 * them, create them:
 */
select * from drop_indexes('public', 'users');
create index users_location on users(location);
create index users_websiteurl on users(websiteurl);


/* We were tuning this query: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> ''
order by u.reputation desc
limit 100;

/* Make a note of buffers read:
 * By index: 5
 * By heap scan: ~2200
 * About 17MB in total
 * 
 * 
 * 
 * Our query is filtering by both location AND websiteurl,
 * so why not create a single index on both?
 */
create index users_location_websiteurl on users(location, websiteurl);


/* Rerun our query. Does Postgres use it? */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> '' 
order by u.reputation desc
limit 100;


/* Did it use the index? If not, force it by dropping the old index: */
drop index users_location;

/* And rerun the query, and ask:
 * About how many buffers get read? 
 * 		By index:
 * 		By heap scan:
 * Is that any better than what we had before? Why or why not?
 * 
 * 
 * Think about the sizes of the location index vs the one on location AND websiteurl:
 */
create index users_location on users(location);

select * from check_indexes('public', 'users');


/* The more columns we use in an index,
 * the more space it takes to write those columns on the 8KB pages of the index,
 * and reading through that data will take more time.
 * 
 * Here's what the index looks like on just location:
 */
create index users_location on users(location);

/* Visualized as: */
select location, ctid
from users u
where u.location = 'Helsinki, Finland'
order by location;

/* And here's what the index on location, websiteurl looks like: */
create index users_location_websiteurl on users(location, websiteurl);

/* Visualized as: */
select location, websiteurl, ctid
from users u
where u.location = 'Helsinki, Finland'
order by location, websiteurl;


/* The second index is physically bigger because it stores more columns,
 * so to read any given number of rows (say, 1000), it'll take more
 * reads to accomplish on the second index, because the second index
 * stores less rows per page.
 * 
 * Postgres is trying to read as little as possible.
 * 
 * Me personally, I would have thought Postgres would be able to
 * use the second index to:
 * 		1. Skip past the '' websiteurls, starting with the first <> '' one
 * 		2. Read all the ones with websiteurls
 * 		3. Stop reading as soon as it hit the nulls
 * 
 * And I would have thought that would end up in less buffer reads.
 * 
 * But what do I know? I'm just a guy, standing in front of a database,
 * asking it to love him.
 * 
 * The end result is just that Postgres seems to love single-column
 * indexes in most use cases.
 * 
 * 
 * 
 * 
 * When is that NOT true? Let's say our query actually used
 * the order of the second column. Let's say instead of sorting
 * by reputation....
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> '' 
order by u.reputation desc
limit 100;


/* Let's say instead we sorted by websiteurl: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl <> '' 
order by u.websiteurl
limit 100;

/* Does Postgres use our location_websiteurl index?
 * 
 * Are we sure the index exists?
 */
select * from check_indexes('public', 'users');



/* Well... Postgres is free, anyway.
 * 
 * One more try - let's also add a VERY selective filter on websiteurl:
 */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'Helsinki, Finland'
  and u.websiteurl = 'http://lmgtfy.com'
order by u.websiteurl
limit 100;



/* And now it gets used. Another example, a very UNselective filter: */
EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.location = 'India'
order by u.websiteurl
limit 100;


/* Takeaway so far:
 * 
 * Seriously, start with single-column indexes, and most of the time,
 * Postgres does a great job of combining them.
 * 
 * If a wider index exists, that's cool, and Postgres may use it...
 * but it may not, especially since its size will be larger,
 * and plus, it's gonna slow down inserts and updates even more
 * than a single-column index would.
 * 
 * 
 * 
 * 
 * 
 * 
 * 
 * But say for a second that we keep the index on
 * location, websiteurl and drop the others:
 */
drop index users_location;
drop index users_websiteurl;
select * from check_indexes('public', 'users');


/* We DO have an index on location, websiteurl.
 * 
 * That does NOT mean "we have an index on websiteurl."
 * 
 * Because if our query is ONLY filtering on websiteurl,
 * and is NOT filtering on the first index column (location),
 * like this:
 */ 

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.websiteurl = 'https://www.brentozar.com';


/* Did Postgres use the index on location_websiteurl?
 * 
 * 
 * 
 * HOW did it use the index?
 * 
 * How much did it read? What's the size of the entire index?
 */
select * from check_indexes('public', 'users');




/* Things to discuss:
 * The explain plan only shows the index - but did the index have all the data we asked for?
 * How did Postgres access the index: seek or scan?
 * How much of the index did Postgres read?
 * 		(Use check_indexes to see the size of the index,
 * 		versus the MB read in Dalibo's explain plan - same as index size)
 * 
 * Did the index actually help? If we didn't have the index,
 * 		how many buffers would we have read?
 * Scanning the entire index is still less reads than doing a heap scan,
 * 		so the index can be technically helpful, but not as helpful
 * 		as an index that lets us dive-bomb into exactly the part of the
 * 		table that we want.
 * 
 * Note our buffer reads:
 * 		On index:
 * 		On heap: (unknown)
*/
create index users_websiteurl on users(websiteurl);

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.reputation, u.displayname, u.websiteurl, u.location, u.id, u.aboutme
from users u
where u.websiteurl = 'https://www.brentozar.com';

/* Things to discuss:
 * Where did Postgres get the data from now?
 * How many buffers did we read?
 * 
 * Even though we had this index that was technically on websiteurl:
 */
create index users_location_websiteurl on users(location, websiteurl);



/* Takeaways:
 * 
 * Multi-column indexes can get used even if we're not filtering
 * on the first column in the index.
 * 
 * However, the explain plan is a little deceiving: we're probably
 * reading the ENTIRE index rather than just diving into the
 * specific rows we need.
 * 
 * Multi-column indexes can be faster than a heap scan, but...
 * 
 * We're still probably better off with specific single-column
 * indexes, which will be more flexible with more queries.
 * 
 * 
 * Disclaimer: this is a fundamentals class, targeted at folks
 * who are just doing their first index designs in Postgres.
 * If you've got 25 years of experience in Postgres, you probably
 * wanna yell at the screen right about now, talking about how
 * there was this one time when a multi-column index saved the
 * day and actually made you look competent. I agree, I create
 * multi-column indexes all the time too, but remember the class
 * you're in right now. Kthxbai.
 */
