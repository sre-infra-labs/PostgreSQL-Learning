/* Leaderboard */
select *
from users u
where u.location <> ''
  and u.displayname <> ''
  and u.websiteurl <> ''
order by reputation desc
limit 100;