use StackOverflow
go

exec sp_BlitzIndex @TableName = 'Users';
go

drop index DisplayName on dbo.Users;
create index DisplayName_Location on dbo.Users (DisplayName, Location);
go

select *
from dbo.Users u
where u.DisplayName in ('Ajay','David')
and u.Location = 'India'
go

/* MSSQL

Engine is able to perform 2 seek operations.
First for DisplayName = 'Ajay' & Location = 'India'
Second for DisplayName = 'David' & Location = 'India'
*/

/* ********************************************************************************************************************* */
create index users__display_name__location on users (displayname, location);

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT *
FROM users u
WHERE u.displayname in ('Ajay','David')
  AND u.location = 'India'
-- Index not used

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT *
FROM users u
WHERE u.displayname ILIKE ANY (ARRAY['Ajay', 'David'])
  AND u.location ILIKE 'India';
-- Index not used

create index users__display_name_lowercase__location_lowercase on users (lower(displayname), lower(location));

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT *
FROM users u
WHERE lower(u.displayname) in (lower('Ajay'), lower('David'))
  AND lower(u.location) = lower('India');
-- Bitmap Index Scan 


/* ***************************** CONCLUSION ********************************* */

SQLServer engine took approx 10 ms.

PG engine took 1 ms with index users__display_name__location with CASE SENSITIVE comparision.
PG engine took 5 seconds with index users__display_name__location with CASE INSENSITIVE comparision.
PG engine took 1 ms with index users__display_name_lowercase__location_lowercase.

