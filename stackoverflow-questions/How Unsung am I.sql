-- https://data.stackexchange.com/stackoverflow/query/7521/how-unsung-am-i
-- https://explain.dalibo.com/plan/505d9312dcf524b9

-- How Unsung am I?
-- Zero and non-zero accepted count. Self-accepted answers do not count.

set search_path to public;

EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
SELECT
    COUNT(a.id) AS "Accepted Answers",
    SUM(CASE WHEN a.score = 0 THEN 0 ELSE 1 END) AS "Scored Answers",  
    SUM(CASE WHEN a.score = 0 THEN 1 ELSE 0 END) AS "Unscored Answers",
    SUM(CASE WHEN a.score = 0 THEN 1 ELSE 0 END) * 1000 / COUNT(a.id) / 10.0 AS "Percentage Unscored"
FROM
    posts q
INNER JOIN
    posts a
ON 
    a.id = q.acceptedanswerid
WHERE
    a.communityowneddate IS NULL
    AND a.owneruserid = 26837
    AND q.owneruserid != 26837
    AND a.posttypeid = 2;

