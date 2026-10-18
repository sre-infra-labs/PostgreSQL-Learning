/* Recent Logins */
select u.displayname, u.reputation, u.location, u.lastaccessdate, u.id
from users u
order by lastaccessdate desc
limit 100;