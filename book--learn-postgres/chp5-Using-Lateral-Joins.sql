/*
    Using Laternal Join
    -------------------

A lateral join is a type of join in SQL that allows you to join a table with a subquery,
  where the subquery is run for each row of the main table.

\c stackoverflow2010
*/

-- Get top 10 users by reputation, and fetch their highest scored question
select u.id, u.reputation, u.displayname, u.location, p.title, p.score
from users u
join lateral (select p.title, p.score from posts p where p.owneruserid = u.id and p.posttypeid = 1 order by p.score desc limit 1) p on true
order by u.reputation desc
limit 10;

