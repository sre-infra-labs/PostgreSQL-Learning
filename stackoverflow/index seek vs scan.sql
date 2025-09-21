/* public.users

stackoverflow=# \d users
                              Table "public.users"
     Column      |            Type             | Collation | Nullable | Default 
-----------------+-----------------------------+-----------+----------+---------
 id              | integer                     |           | not null | 
 reputation      | integer                     |           |          | 
 creationdate    | timestamp without time zone |           |          | 
 displayname     | character varying(40)       |           |          | 
 lastaccessdate  | timestamp without time zone |           |          | 
 websiteurl      | character varying(200)      |           |          | 
 location        | character varying(100)      |           |          | 
 aboutme         | text                        |           |          | 
 views           | integer                     |           |          | 
 upvotes         | integer                     |           |          | 
 downvotes       | integer                     |           |          | 
 profileimageurl | character varying(200)      |           |          | 
 emailhash       | character varying(32)       |           |          | 
 accountid       | integer                     |           |          | 
Indexes:
    "pk_users__id" PRIMARY KEY, btree (id)
    "users_displayname" btree (displayname)
    "users_length_displayname" btree (length(displayname::text))
    "users_location_displayname" btree (location, displayname)

*/

--EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.id, u.displayname
from public.users u
where displayname = 'Ajay Dwivedi'
limit 100

/*  Sargable Argument

Limit  (cost=0.56..144.56 rows=35 width=16) (actual time=0.025..0.032 rows=8 loops=1)
  Output: id, displayname
  Buffers: shared hit=12
  ->  Index Scan using users_displayname on public.users u  (cost=0.56..144.56 rows=35 width=16) (actual time=0.025..0.031 rows=8 loops=1)
        Output: id, displayname
        Index Cond: ((u.displayname)::text = 'Ajay Dwivedi'::text)
        Buffers: shared hit=12
Planning Time: 0.073 ms
Execution Time: 0.042 ms


*/



--EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select u.id, u.displayname
from public.users u
where lower(displayname) = lower('Ajay Dwivedi')
limit 100

/*  Non-Sargable Argument

Limit  (cost=0.00..619.12 rows=100 width=16) (actual time=863.099..5175.826 rows=8 loops=1)
  Output: id, displayname
  Buffers: shared hit=41 read=344735
  ->  Seq Scan on public.users u  (cost=0.00..668898.46 rows=108041 width=16) (actual time=863.098..5175.818 rows=8 loops=1)
        Output: id, displayname
        Filter: (lower((u.displayname)::text) = 'ajay dwivedi'::text)
        Rows Removed by Filter: 21608155
        Buffers: shared hit=41 read=344735
Planning Time: 0.066 ms
Execution Time: 5175.842 ms

*/



/*  QUERY in SQLServer

--exec sp_BlitzIndex @TableName = 'users'

create index displayname on dbo.Users (displayname);
go

set statistics profile off;
select top 100 
        u.id, u.displayname
from dbo.users u
where displayname = 'Ajay Dwivedi';


set statistics profile on;
select top 100
        u.id, u.displayname
from dbo.users u
where lower(displayname) = lower('Ajay Dwivedi');
*/