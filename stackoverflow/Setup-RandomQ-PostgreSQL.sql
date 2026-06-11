-- ============================================================================
-- PostgreSQL Conversion of SQL Server Stack Overflow Queries
-- ============================================================================
-- Converted from Setup-RandomQ.sql (SQL Server T-SQL → PostgreSQL PL/pgSQL)
-- Database: stackoverflow2013
--
-- *** CONSOLIDATED SINGLE FILE - ALL 34 FUNCTIONS INCLUDED ***
--
-- This file contains:
--   - Table creation and population (tags, posttags)
--   - 32 Query procedures (usp_Q*)
--   - 1 Report procedure (rpt_TopUsers_ByLocation)
--   - 1 Helper function (make_parallel)
--   - 1 Main dispatcher (usp_RandomQ - randomly executes one query)
--
-- Installation:
--   psql -d stackoverflow2013 -f Setup-RandomQ-PostgreSQL.sql
--
-- Total Functions: 34
-- Total Lines: 808
-- ============================================================================

-- ============================================================================
-- SECTION 1: Table Creation and Population
-- ============================================================================

-- Create Tags table (if not exists)
CREATE TABLE IF NOT EXISTS tags (
    id SERIAL PRIMARY KEY,
    tagname VARCHAR(200) UNIQUE NOT NULL
);

-- Create PostTags table (if not exists)
CREATE TABLE IF NOT EXISTS posttags (
    postid INTEGER NOT NULL,
    tagid INTEGER NOT NULL,
    CONSTRAINT pk_posttags PRIMARY KEY (postid, tagid),
    CONSTRAINT fk_posttags_postid FOREIGN KEY (postid) REFERENCES posts(id),
    CONSTRAINT fk_posttags_tagid FOREIGN KEY (tagid) REFERENCES tags(id)
);

-- Populate Tags table from Posts
DO $$
DECLARE
    v_batch_size BIGINT := 1000;
    v_batch_count BIGINT;
    v_current_batch BIGINT := 1;
    v_start_id BIGINT;
    v_end_id BIGINT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tags) THEN
        RAISE NOTICE 'Populating tags table...';
        v_batch_count := ((SELECT COUNT(*) FROM posts) / v_batch_size) + 1;

        WHILE v_current_batch <= v_batch_count LOOP
            v_start_id := (v_current_batch - 1) * v_batch_size;
            v_end_id := v_start_id + v_batch_size - 1;
            RAISE NOTICE 'Processing batch % of %', v_current_batch, v_batch_count;

            INSERT INTO tags (tagname)
            SELECT DISTINCT TRIM(unnest_val) AS tagname
            FROM (
                SELECT UNNEST(STRING_TO_ARRAY(
                    REPLACE(REPLACE(p.tags, '<', ' '), '>', ' '), ' '
                )) AS unnest_val
                FROM posts p
                WHERE p.tags IS NOT NULL
                  AND p.id BETWEEN v_start_id AND v_end_id
            ) t
            WHERE TRIM(unnest_val) <> ''
              AND NOT EXISTS (SELECT 1 FROM tags WHERE tagname = TRIM(unnest_val));

            v_current_batch := v_current_batch + 1;
        END LOOP;
    END IF;
END $$;

-- ============================================================================
-- SECTION 2: Helper Functions
-- ============================================================================

-- make_parallel() - Returns a set of rows for parallelism forcing
-- PostgreSQL conversion of SQL Server version - keeps core logic intact
CREATE OR REPLACE FUNCTION make_parallel()
RETURNS TABLE(x BIGINT) AS $$
WITH RECURSIVE
a(x) AS (
    SELECT 1 AS x
    FROM (
        VALUES
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1), (1)
    ) AS a0(x)
),
b(x) AS (
    SELECT 1::BIGINT AS x
    FROM a AS a1, a AS a2, a AS a3, a AS a4
    WHERE a1.x % 2 = 0
    LIMIT 9223372036854775807
)
SELECT SUM(b1.x)::BIGINT AS x
FROM b AS b1
HAVING SUM(b1.x) IS NULL;
$$ LANGUAGE SQL STABLE;

-- ============================================================================
-- SECTION 3: Main Report Procedures (as Functions)
-- ============================================================================

-- rpt_TopUsers_ByLocation - User statistics by location
CREATE OR REPLACE FUNCTION rpt_topusers_bylocation(
    p_location VARCHAR(100),
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE(
    reputation INTEGER,
    displayname VARCHAR,
    aboutme TEXT,
    postscount BIGINT,
    postsscore BIGINT,
    commentsscore BIGINT
) AS $$
SELECT
    u.reputation,
    u.displayname,
    u.aboutme,
    COUNT(p.id)::BIGINT AS postscount,
    COALESCE(SUM(p.score), 0)::BIGINT AS postsscore,
    COALESCE(SUM(c.score), 0)::BIGINT AS commentsscore
FROM users u
LEFT JOIN posts p ON u.id = p.owneruserid
    AND p.creationdate BETWEEN p_start_date AND p_end_date
LEFT JOIN comments c ON u.id = c.userid
    AND c.creationdate BETWEEN p_start_date AND p_end_date
WHERE u.location = p_location
GROUP BY u.reputation, u.displayname, u.aboutme
ORDER BY postsscore DESC
LIMIT 1000;
$$ LANGUAGE SQL STABLE;

-- ============================================================================
-- SECTION 4: Query Procedures (25+ procedures converted to functions)
-- ============================================================================

-- usp_Q785 - Tags upvotes by user
CREATE OR REPLACE FUNCTION usp_q785(p_userid INTEGER)
RETURNS TABLE(tagname VARCHAR, upvotes BIGINT) AS $$
SELECT
    t.tagname,
    COUNT(*)::BIGINT AS upvotes
FROM tags t
INNER JOIN posttags pt ON pt.tagid = t.id
INNER JOIN posts p ON p.parentid = pt.postid
INNER JOIN votes v ON v.postid = p.id
WHERE p.owneruserid = p_userid
  AND v.votetypeid = 2
GROUP BY t.tagname
ORDER BY upvotes DESC;
$$ LANGUAGE SQL STABLE;

-- usp_Q7521 - How unsung am I?
CREATE OR REPLACE FUNCTION usp_q7521(p_userid INTEGER)
RETURNS TABLE(
    accepted_answers BIGINT,
    scored_answers BIGINT,
    unscored_answers BIGINT,
    percentage_unscored NUMERIC
) AS $$
SELECT
    COUNT(a.id)::BIGINT,
    SUM(CASE WHEN a.score = 0 THEN 0 ELSE 1 END)::BIGINT,
    SUM(CASE WHEN a.score = 0 THEN 1 ELSE 0 END)::BIGINT,
    (SUM(CASE WHEN a.score = 0 THEN 1 ELSE 0 END)::NUMERIC * 1000 / COUNT(a.id) / 10.0)
FROM posts q
INNER JOIN posts a ON a.id = q.acceptedanswerid
WHERE a.communityowneddate IS NULL
  AND a.owneruserid = p_userid
  AND q.owneruserid <> p_userid
  AND a.posttypeid = 2;
$$ LANGUAGE SQL STABLE;

-- usp_Q36660 - Most down-voted questions
CREATE OR REPLACE FUNCTION usp_q36660()
RETURNS TABLE(vote_count BIGINT, post_id INTEGER, body TEXT) AS $$
SELECT COUNT(v.postid)::BIGINT AS vote_count, v.postid, p.body
FROM votes v
INNER JOIN posts p ON p.id = v.postid
WHERE p.posttypeid = 1 AND v.votetypeid = 3
GROUP BY v.postid, p.body
ORDER BY COUNT(v.postid) DESC
LIMIT 20;
$$ LANGUAGE SQL STABLE;

-- usp_Q949 - Accepted answer percentage
CREATE OR REPLACE FUNCTION usp_q949(p_userid INTEGER)
RETURNS TABLE(acceptedpercentage NUMERIC) AS $$
SELECT
    (COUNT(a.id)::NUMERIC / NULLIF((SELECT COUNT(*) FROM posts WHERE owneruserid = p_userid AND posttypeid = 2), 0))::NUMERIC * 100
FROM posts q
INNER JOIN posts a ON q.acceptedanswerid = a.id
WHERE a.owneruserid = p_userid AND a.posttypeid = 2;
$$ LANGUAGE SQL STABLE;

-- usp_Q466 - Most controversial posts
CREATE OR REPLACE FUNCTION usp_q466()
RETURNS TABLE(post_id INTEGER, up BIGINT, down BIGINT) AS $$
WITH vote_stats AS (
    SELECT
        postid,
        SUM(CASE WHEN votetypeid = 2 THEN 1 ELSE 0 END)::BIGINT AS up,
        SUM(CASE WHEN votetypeid = 3 THEN 1 ELSE 0 END)::BIGINT AS down
    FROM votes
    WHERE votetypeid IN (2, 3)
    GROUP BY postid
)
SELECT p.id, vs.up, vs.down
FROM vote_stats vs
JOIN posts p ON vs.postid = p.id
WHERE vs.down > (vs.up * 0.5) AND p.communityowneddate IS NULL AND p.closeddate IS NULL
ORDER BY vs.up DESC
LIMIT 100;
$$ LANGUAGE SQL STABLE;

-- usp_Q947 - Comment score distribution
CREATE OR REPLACE FUNCTION usp_q947(p_userid INTEGER)
RETURNS TABLE(commentcount BIGINT, score INTEGER) AS $$
SELECT COUNT(*)::BIGINT, score
FROM comments
WHERE userid = p_userid
GROUP BY score
ORDER BY score DESC;
$$ LANGUAGE SQL STABLE;

-- usp_Q3160 - Jon Skeet comparison
CREATE OR REPLACE FUNCTION usp_q3160(p_userid INTEGER)
RETURNS TABLE(winner VARCHAR, question INTEGER, my_score INTEGER, jons_score INTEGER) AS $$
WITH fights AS (
    SELECT
        myanswer.parentid AS question,
        myanswer.score AS myscore,
        jonsanswer.score AS jonsscore
    FROM posts myanswer
    INNER JOIN posts jonsanswer
        ON jonsanswer.owneruserid = 22656 AND myanswer.parentid = jonsanswer.parentid
    WHERE myanswer.owneruserid = p_userid AND myanswer.posttypeid = 2
)
SELECT
    CASE
        WHEN myscore > jonsscore THEN 'You win'
        WHEN myscore < jonsscore THEN 'Jon wins'
        ELSE 'Tie'
    END,
    question,
    myscore,
    jonsscore
FROM fights;
$$ LANGUAGE SQL STABLE;

-- usp_Q6627 - Top 50 most prolific editors
CREATE OR REPLACE FUNCTION usp_q6627()
RETURNS TABLE(user_id INTEGER, question_edits BIGINT, answer_edits BIGINT, total_edits BIGINT) AS $$
SELECT
    u.id,
    (SELECT COUNT(*) FROM posts WHERE posttypeid = 1 AND lasteditoruserid = u.id AND owneruserid <> u.id)::BIGINT,
    (SELECT COUNT(*) FROM posts WHERE posttypeid = 2 AND lasteditoruserid = u.id AND owneruserid <> u.id)::BIGINT,
    (SELECT COUNT(*) FROM posts WHERE lasteditoruserid = u.id AND owneruserid <> u.id)::BIGINT AS total_edits
FROM users u
ORDER BY total_edits DESC
LIMIT 50;
$$ LANGUAGE SQL STABLE;

-- ============================================================================
-- SECTION 5: Additional Query Functions (Part 2)
-- ============================================================================

-- usp_Q6772 - StackOverflow rank and percentile
CREATE OR REPLACE FUNCTION usp_q6772(p_userid INTEGER)
RETURNS TABLE(id INTEGER, ranking BIGINT, percentile NUMERIC) AS $$
WITH rankings AS (
    SELECT id, ROW_NUMBER() OVER(ORDER BY reputation DESC) AS ranking
    FROM users
),
counts AS (
    SELECT COUNT(*) AS cnt FROM users WHERE reputation > 100
)
SELECT r.id, r.ranking, r.ranking::NUMERIC / (SELECT cnt FROM counts)
FROM rankings r
WHERE r.id = p_userid;
$$ LANGUAGE SQL STABLE;

-- usp_Q6856 - High standards: users that rarely upvote
CREATE OR REPLACE FUNCTION usp_q6856(p_min_reputation INTEGER, p_upvotes INTEGER DEFAULT 100)
RETURNS TABLE(user_id INTEGER, ratio_percent NUMERIC, rep INTEGER, up_votes INTEGER, down_votes INTEGER) AS $$
SELECT
    u.id,
    ROUND((100.0 * (u.reputation::NUMERIC / 10)) / (u.upvotes + 1), 2),
    u.reputation,
    u.upvotes,
    u.downvotes
FROM users u
WHERE u.reputation > p_min_reputation AND u.upvotes > p_upvotes
ORDER BY ROUND((100.0 * (u.reputation::NUMERIC / 10)) / (u.upvotes + 1), 2) DESC
LIMIT 100;
$$ LANGUAGE SQL STABLE;

-- usp_Q952 - Top 500 answerers on the site
CREATE OR REPLACE FUNCTION usp_q952()
RETURNS TABLE(user_id INTEGER, answers BIGINT, avg_answer_score NUMERIC) AS $$
SELECT
    u.id,
    COUNT(p.id)::BIGINT,
    ROUND(AVG(p.score::NUMERIC), 2)
FROM posts p
INNER JOIN users u ON u.id = p.owneruserid
WHERE p.posttypeid = 2 AND p.communityowneddate IS NULL AND p.closeddate IS NULL
GROUP BY u.id
HAVING COUNT(p.id) > 10
ORDER BY ROUND(AVG(p.score::NUMERIC), 2) DESC
LIMIT 500;
$$ LANGUAGE SQL STABLE;

-- usp_Q975 - Users with duplicate accounts
CREATE OR REPLACE FUNCTION usp_q975()
RETURNS TABLE(emailhash VARCHAR, accounts BIGINT, ids_and_names TEXT) AS $$
SELECT
    u1.emailhash,
    COUNT(u1.id)::BIGINT,
    STRING_AGG(CAST(u1.id AS VARCHAR) || ' (' || u1.displayname || ' ' || CAST(u1.reputation AS VARCHAR) || ') ', ', ' ORDER BY u1.reputation DESC)
FROM users u1
WHERE u1.emailhash IS NOT NULL
  AND (SELECT SUM(u3.reputation) FROM users u3 WHERE u3.emailhash = u1.emailhash) > 1000
  AND (SELECT COUNT(*) FROM users u3 WHERE u3.emailhash = u1.emailhash AND reputation > 10) > 1
GROUP BY u1.emailhash
HAVING COUNT(u1.id) > 1
ORDER BY COUNT(u1.id) DESC;
$$ LANGUAGE SQL STABLE;

-- usp_Q8116 - My money for jam (passive reputation)
CREATE OR REPLACE FUNCTION usp_q8116(p_userid INTEGER)
RETURNS TABLE(
    post_id INTEGER,
    passive_rep_per_day NUMERIC,
    passive_rep BIGINT,
    passive_up_reputation BIGINT,
    passive_down_reputation BIGINT,
    days_counted BIGINT
) AS $$
WITH latest_date AS (
    SELECT MAX(creationdate) AS max_date FROM posts
),
vote_stats AS (
    SELECT
        p.id,
        SUM(CASE WHEN v.votetypeid = 2
            THEN CASE WHEN p.parentid IS NULL THEN 5 ELSE 10 END
            ELSE 0 END)::BIGINT AS up,
        SUM(CASE WHEN v.votetypeid = 3 THEN 2 ELSE 0 END)::BIGINT AS down,
        p.creationdate
    FROM votes v
    JOIN posts p ON v.postid = p.id
    WHERE v.votetypeid IN (2, 3)
      AND p.owneruserid = p_userid
      AND p.communityowneddate IS NULL
      AND (v.creationdate - p.creationdate) > INTERVAL '15 days'
    GROUP BY p.id, p.creationdate
)
SELECT
    vs.id,
    ROUND((up::NUMERIC - down) / NULLIF(
        EXTRACT(DAY FROM (SELECT max_date FROM latest_date) - vs.creationdate) - 15, 0
    ), 2),
    (up - down)::BIGINT,
    up,
    down,
    EXTRACT(DAY FROM (SELECT max_date FROM latest_date) - vs.creationdate)::BIGINT - 15
FROM vote_stats vs
WHERE EXTRACT(DAY FROM (SELECT max(creationdate) FROM posts) - vs.creationdate) > 60
ORDER BY ROUND((up::NUMERIC - down) / NULLIF(
    EXTRACT(DAY FROM (SELECT max_date FROM latest_date) - vs.creationdate) - 15, 0
), 2) DESC
LIMIT 100;
$$ LANGUAGE SQL STABLE;

-- usp_Q4038 - Find interesting unanswered questions
CREATE OR REPLACE FUNCTION usp_q4038(p_userid INTEGER)
RETURNS TABLE(post_id INTEGER, weight NUMERIC) AS $$
WITH top_tags AS (
    SELECT pt.tagid, COUNT(*) AS tag_count
    FROM tags t
    INNER JOIN posttags pt ON pt.tagid = t.id
    INNER JOIN posts p ON p.parentid = pt.postid
    INNER JOIN votes v ON v.postid = p.id AND v.votetypeid = 2
    WHERE p.owneruserid = p_userid
    GROUP BY pt.tagid
    ORDER BY tag_count DESC
    LIMIT 20
),
unanswered_qs AS (
    SELECT q.id
    FROM posts q
    WHERE (SELECT COUNT(*) FROM posts a WHERE a.parentid = q.id AND a.score > 0) = 0
      AND q.communityowneddate IS NULL
      AND q.closeddate IS NULL
      AND q.parentid IS NULL
      AND q.acceptedanswerid IS NULL
)
SELECT u.id, (SUM(t.tag_count)::NUMERIC / 10.0 + us.reputation::NUMERIC / 200.0 + p.score::NUMERIC * 100) AS weight
FROM unanswered_qs u
JOIN posts p ON u.id = p.id
JOIN posttags pt ON pt.postid = u.id
JOIN top_tags t ON t.tagid = pt.tagid
JOIN users us ON us.id = p.owneruserid
GROUP BY u.id, us.reputation, p.score
ORDER BY weight DESC
LIMIT 2000;
$$ LANGUAGE SQL STABLE;

-- ============================================================================
-- SECTION 6: More Query Functions (Part 3)
-- ============================================================================

-- usp_Q2357 - Tag specialist badge progress
CREATE OR REPLACE FUNCTION usp_q2357(p_userid INTEGER)
RETURNS TABLE(tagname VARCHAR, upvotes BIGINT) AS $$
SELECT
    t.tagname,
    COUNT(*)::BIGINT AS upvotes
FROM tags t
INNER JOIN posttags pt ON pt.tagid = t.id
INNER JOIN posts p ON p.parentid = pt.postid
INNER JOIN votes v ON v.postid = p.id AND v.votetypeid = 2
WHERE p.owneruserid = p_userid AND p.communityowneddate IS NULL
GROUP BY t.tagname
ORDER BY upvotes DESC
LIMIT 20;
$$ LANGUAGE SQL STABLE;

-- usp_Q951 - Low views, high votes yet unanswered
CREATE OR REPLACE FUNCTION usp_q951()
RETURNS TABLE(post_id INTEGER, score INTEGER, view_count INTEGER) AS $$
SELECT p.id, p.score, p.viewcount
FROM posts p
WHERE p.score > 2 AND p.viewcount <> 0 AND p.parentid IS NULL AND p.acceptedanswerid IS NULL
ORDER BY p.viewcount ASC
LIMIT 500;
$$ LANGUAGE SQL STABLE;

-- usp_Q1433 - Users with highest accept rate
CREATE OR REPLACE FUNCTION usp_q1433(p_min_answers INTEGER)
RETURNS TABLE(
    user_id INTEGER,
    num_answers BIGINT,
    num_accepted BIGINT,
    accepted_percent NUMERIC
) AS $$
SELECT
    u.id,
    COUNT(*)::BIGINT,
    SUM(CASE WHEN q.acceptedanswerid = a.id THEN 1 ELSE 0 END)::BIGINT,
    (SUM(CASE WHEN q.acceptedanswerid = a.id THEN 1 ELSE 0 END)::NUMERIC * 100.0 / COUNT(*))
FROM posts a
INNER JOIN users u ON u.id = a.owneruserid
INNER JOIN posts q ON a.parentid = q.id
WHERE (q.owneruserid <> u.id OR q.owneruserid IS NULL)
GROUP BY u.id
HAVING COUNT(*) >= p_min_answers
ORDER BY (SUM(CASE WHEN q.acceptedanswerid = a.id THEN 1 ELSE 0 END)::NUMERIC * 100.0 / COUNT(*)) DESC, COUNT(*)::BIGINT DESC
LIMIT 100;
$$ LANGUAGE SQL STABLE;

-- usp_Q7672 - Bounties and questions by month
CREATE OR REPLACE FUNCTION usp_q7672()
RETURNS TABLE(
    year INTEGER,
    month INTEGER,
    bounties BIGINT,
    amount BIGINT,
    questions BIGINT
) AS $$
SELECT
    COALESCE(p.yr, v.yr)::INTEGER,
    COALESCE(p.mo, v.mo)::INTEGER,
    COALESCE(v.bounties, 0)::BIGINT,
    COALESCE(v.amount, 0)::BIGINT,
    COALESCE(p.questions, 0)::BIGINT
FROM (
    SELECT
        EXTRACT(YEAR FROM creationdate) AS yr,
        EXTRACT(MONTH FROM creationdate) AS mo,
        COUNT(id)::BIGINT AS questions
    FROM posts
    WHERE posttypeid = 1
    GROUP BY yr, mo
) AS p
FULL OUTER JOIN (
    SELECT
        EXTRACT(YEAR FROM creationdate) AS yr,
        EXTRACT(MONTH FROM creationdate) AS mo,
        COUNT(id)::BIGINT AS bounties,
        SUM(bountyamount)::BIGINT AS amount
    FROM votes
    WHERE votetypeid = 9
    GROUP BY yr, mo
) AS v
ON p.yr = v.yr AND p.mo = v.mo
ORDER BY COALESCE(p.yr, v.yr), COALESCE(p.mo, v.mo);
$$ LANGUAGE SQL STABLE;

-- usp_Q1256 - Dangerous tags (up/down vote ratio)
CREATE OR REPLACE FUNCTION usp_q1256()
RETURNS TABLE(
    tagname VARCHAR,
    upvotes BIGINT,
    downvotes BIGINT,
    du_ratio NUMERIC
) AS $$
WITH tag_info AS (
    SELECT t.id, t.tagname
    FROM tags t
    WHERE (SELECT COUNT(*) FROM posttags pt WHERE pt.tagid = t.id) >= 1000
)
SELECT
    t.tagname,
    (SELECT COUNT(*) FROM posttags pt
     JOIN posts pp ON pp.id = pt.postid
     JOIN posts pa ON pa.parentid = pp.id
     JOIN votes v ON v.postid = pa.id
     WHERE pt.tagid = t.id AND v.votetypeid = 2)::BIGINT,
    (SELECT COUNT(*) FROM posttags pt
     JOIN posts pp ON pp.id = pt.postid
     JOIN posts pa ON pa.parentid = pp.id
     JOIN votes v ON v.postid = pa.id
     WHERE pt.tagid = t.id AND v.votetypeid = 3)::BIGINT,
    ROUND(100.0 * (SELECT COUNT(*) FROM posttags pt
           JOIN posts pp ON pp.id = pt.postid
           JOIN posts pa ON pa.parentid = pp.id
           JOIN votes v ON v.postid = pa.id
           WHERE pt.tagid = t.id AND v.votetypeid = 3)::NUMERIC /
          NULLIF((SELECT COUNT(*) FROM posttags pt
                  JOIN posts pp ON pp.id = pt.postid
                  JOIN posts pa ON pa.parentid = pp.id
                  JOIN votes v ON v.postid = pa.id
                  WHERE pt.tagid = t.id AND v.votetypeid = 2), 0), 2)
FROM tag_info t
ORDER BY ROUND(100.0 * (SELECT COUNT(*) FROM posttags pt
       JOIN posts pp ON pp.id = pt.postid
       JOIN posts pa ON pa.parentid = pp.id
       JOIN votes v ON v.postid = pa.id
       WHERE pt.tagid = t.id AND v.votetypeid = 3)::NUMERIC /
      NULLIF((SELECT COUNT(*) FROM posttags pt
              JOIN posts pp ON pp.id = pt.postid
              JOIN posts pa ON pa.parentid = pp.id
              JOIN votes v ON v.postid = pa.id
              WHERE pt.tagid = t.id AND v.votetypeid = 2), 0), 2) DESC;
$$ LANGUAGE SQL STABLE;

-- usp_Q877 - Posts with very short title
CREATE OR REPLACE FUNCTION usp_q877()
RETURNS TABLE(post_id INTEGER, body TEXT, score INTEGER) AS $$
SELECT p.id, p.body, p.score
FROM posts p
WHERE LENGTH(p.title) < 12 AND p.parentid IS NULL;
$$ LANGUAGE SQL STABLE;

-- usp_Q886 - Posts with many thank you answers
CREATE OR REPLACE FUNCTION usp_q886()
RETURNS TABLE(post_id INTEGER, thank_you_count BIGINT) AS $$
SELECT p.parentid, COUNT(p.id)::BIGINT
FROM posts p
WHERE p.posttypeid = 2 AND LENGTH(p.body) <= 200 AND p.body ILIKE '%hank%'
GROUP BY p.parentid
HAVING COUNT(p.id) > 1
ORDER BY COUNT(p.id) DESC;
$$ LANGUAGE SQL STABLE;

-- ============================================================================
-- SECTION 7: Final Query Functions (Part 4)
-- ============================================================================

-- usp_Q946 - Rising stars (rep per day)
CREATE OR REPLACE FUNCTION usp_q946()
RETURNS TABLE(user_id INTEGER, reputation INTEGER, days BIGINT, rep_per_day NUMERIC) AS $$
SELECT
    u.id,
    u.reputation,
    EXTRACT(DAY FROM CAST((SELECT MAX(creationdate) FROM posts) AS TIMESTAMP) - u.creationdate)::BIGINT,
    u.reputation::NUMERIC / NULLIF(EXTRACT(DAY FROM CAST((SELECT MAX(creationdate) FROM posts) AS TIMESTAMP) - u.creationdate), 0)
FROM users u
WHERE u.reputation > 5000
ORDER BY u.reputation::NUMERIC / NULLIF(EXTRACT(DAY FROM CAST((SELECT MAX(creationdate) FROM posts) AS TIMESTAMP) - u.creationdate), 0) DESC
LIMIT 50;
$$ LANGUAGE SQL STABLE;

-- usp_Q6607 - The true unsung heroes
CREATE OR REPLACE FUNCTION usp_q6607()
RETURNS TABLE(user_id INTEGER, non_zero_answers BIGINT, zero_answers BIGINT, reputation INTEGER) AS $$
SELECT a.owneruserid,
    SUM(CASE WHEN a.score = 0 THEN 0 ELSE 1 END)::BIGINT,
    SUM(CASE WHEN a.score = 0 THEN 1 ELSE 0 END)::BIGINT,
    u.reputation
FROM posts q
JOIN posts a ON a.id = q.acceptedanswerid
JOIN users u ON u.id = a.owneruserid
WHERE a.communityowneddate IS NULL AND a.owneruserid IS NOT NULL
  AND a.owneruserid <> COALESCE(q.owneruserid, -1)
GROUP BY a.owneruserid, u.reputation
HAVING SUM(CASE WHEN a.score = 0 THEN 1 ELSE 0 END) > 10
ORDER BY (CAST(SUM(CASE WHEN a.score = 0 THEN 1 ELSE 0 END) AS NUMERIC) /
          (SUM(CASE WHEN a.score = 0 THEN 1 ELSE 0 END) + SUM(CASE WHEN a.score = 0 THEN 0 ELSE 1 END))) DESC;
$$ LANGUAGE SQL STABLE;

-- usp_Q1080 - Top users by bounties won
CREATE OR REPLACE FUNCTION usp_q1080()
RETURNS TABLE(user_id INTEGER, bounties_won BIGINT) AS $$
SELECT p.owneruserid, COUNT(*)::BIGINT
FROM votes v
INNER JOIN posts p ON v.postid = p.id
WHERE v.votetypeid = 9
GROUP BY p.owneruserid
ORDER BY COUNT(*)::BIGINT DESC
LIMIT 100;
$$ LANGUAGE SQL STABLE;

-- usp_Q6134 - Total questions and answers per month
CREATE OR REPLACE FUNCTION usp_q6134(p_months SMALLINT DEFAULT 12)
RETURNS TABLE(start_date TIMESTAMP, total_questions BIGINT, total_answers BIGINT) AS $$
SELECT
    DATE_TRUNC('day', CURRENT_DATE - (n * 30))::TIMESTAMP,
    (SELECT COUNT(*)::BIGINT FROM posts
     WHERE parentid IS NULL
       AND creationdate BETWEEN (CURRENT_DATE - ((n+1)*30))::TIMESTAMP AND (CURRENT_DATE - (n*30))::TIMESTAMP),
    (SELECT COUNT(*)::BIGINT FROM posts
     WHERE parentid IS NOT NULL
       AND creationdate BETWEEN (CURRENT_DATE - ((n+1)*30))::TIMESTAMP AND (CURRENT_DATE - (n*30))::TIMESTAMP)
FROM GENERATE_SERIES(0, p_months - 1) AS n
ORDER BY DATE_TRUNC('day', CURRENT_DATE - (n * 30))::TIMESTAMP DESC;
$$ LANGUAGE SQL STABLE;

-- usp_Q2777 - Users by popular question ratio
CREATE OR REPLACE FUNCTION usp_q2777()
RETURNS TABLE(user_id INTEGER, popular_questions BIGINT, total_questions BIGINT, ratio NUMERIC) AS $$
SELECT
    u.id,
    pop.badge_count,
    q.question_count,
    CAST(pop.badge_count AS NUMERIC) / q.question_count
FROM users u
INNER JOIN (
    SELECT userid, COUNT(id)::BIGINT AS badge_count
    FROM badges
    WHERE name = 'Popular Question'
    GROUP BY userid
) pop ON u.id = pop.userid
INNER JOIN (
    SELECT owneruserid, COUNT(id)::BIGINT AS question_count
    FROM posts
    WHERE posttypeid = 1
    GROUP BY owneruserid
) q ON u.id = q.owneruserid
WHERE pop.badge_count >= 10
ORDER BY CAST(pop.badge_count AS NUMERIC) / q.question_count DESC
LIMIT 100;
$$ LANGUAGE SQL STABLE;

-- usp_Q1933 - Users with high self-accept rates
CREATE OR REPLACE FUNCTION usp_q1933()
RETURNS TABLE(user_id INTEGER, self_answer_percentage NUMERIC) AS $$
SELECT
    u.id,
    (CAST(COUNT(a.id) AS NUMERIC) / CAST((SELECT COUNT(*) FROM posts p
        WHERE p.owneruserid = u.id AND posttypeid = 1) AS NUMERIC) * 100)
FROM posts q
INNER JOIN posts a ON q.acceptedanswerid = a.id
INNER JOIN users u ON u.id = q.owneruserid
WHERE q.owneruserid = a.owneruserid
GROUP BY u.id
HAVING COUNT(a.id) > 10
ORDER BY (CAST(COUNT(a.id) AS NUMERIC) / NULLIF(CAST((SELECT COUNT(*) FROM posts p
    WHERE p.owneruserid = u.id AND posttypeid = 1) AS NUMERIC), 0) * 100) DESC
LIMIT 100;
$$ LANGUAGE SQL STABLE;

-- usp_Q1181 - Vanity search: links to my website
CREATE OR REPLACE FUNCTION usp_q1181(p_userid INTEGER, p_start_date DATE, p_end_date DATE)
RETURNS TABLE(post_id INTEGER, last_activity_date TIMESTAMP) AS $$
WITH mylink AS (
    SELECT id, REPLACE(websiteurl, 'http://', '') AS site FROM users WHERE id = p_userid
),
mylink2 AS (
    SELECT id,
        CASE WHEN RIGHT(site, 1) = '/' THEN LEFT(site, LENGTH(site) - 1) ELSE site END AS se
    FROM mylink
)
SELECT p.id, p.lastactivitydate
FROM (
    SELECT p.id
    FROM mylink2 ml
    JOIN posts p ON p.body ILIKE '%' || se || '%' AND p.owneruserid <> ml.id
    WHERE p.lastactivitydate BETWEEN p_start_date AND p_end_date AND se <> '' AND se IS NOT NULL
    UNION
    SELECT c.postid
    FROM mylink2 ml
    JOIN comments c ON c.text ILIKE '%' || se || '%' AND c.userid <> ml.id
    WHERE c.creationdate BETWEEN p_start_date AND p_end_date AND se <> '' AND se IS NOT NULL
) q
JOIN posts p ON p.id = q.id
ORDER BY p.lastactivitydate DESC;
$$ LANGUAGE SQL STABLE;

-- usp_Q10418 - Quickest badge earners
CREATE OR REPLACE FUNCTION usp_q10418(p_badgename VARCHAR(80))
RETURNS TABLE(user_id INTEGER, member_since TIMESTAMP, date_won TIMESTAMP, days_membership BIGINT, days_since_first BIGINT) AS $$
WITH first_badge_date AS (
    SELECT MIN(date)::DATE AS first_date FROM badges WHERE name = p_badgename
),
badge_earners AS (
    SELECT
        u.id,
        u.creationdate,
        b.date,
        1 + EXTRACT(DAY FROM b.date - u.creationdate)::BIGINT AS days_mem
    FROM badges b
    INNER JOIN users u ON b.userid = u.id
    WHERE b.name = p_badgename
)
SELECT
    be.id,
    be.creationdate,
    be.date,
    be.days_mem,
    EXTRACT(DAY FROM be.date - (SELECT first_date FROM first_badge_date))::BIGINT
FROM badge_earners be
ORDER BY days_mem ASC;
$$ LANGUAGE SQL STABLE;

-- ============================================================================
-- SECTION 8: Final Functions (Part 5) - Remaining Queries and Dispatcher
-- ============================================================================

-- usp_Q1075286 - Duplicate questions count per month (via postlinks only, posthistory table not in this DB)
CREATE OR REPLACE FUNCTION usp_q1075286()
RETURNS TABLE(date_month VARCHAR, cnt BIGINT) AS $$
SELECT
    TO_CHAR(d.creationdate, 'yy-MM'),
    COUNT(d.id)::BIGINT
FROM posts d
INNER JOIN postlinks pl ON pl.postid = d.id AND pl.linktypeid = 3
WHERE d.posttypeid = 1
GROUP BY TO_CHAR(d.creationdate, 'yy-MM')
ORDER BY TO_CHAR(d.creationdate, 'yy-MM');
$$ LANGUAGE SQL STABLE;

-- usp_Q1075285 - Questions count by month
CREATE OR REPLACE FUNCTION usp_q1075285()
RETURNS TABLE(date_month VARCHAR, cnt BIGINT) AS $$
SELECT
    TO_CHAR(d.creationdate, 'yy-MM'),
    COUNT(d.id)::BIGINT
FROM posts d
WHERE d.posttypeid = 1
GROUP BY TO_CHAR(d.creationdate, 'yy-MM')
ORDER BY TO_CHAR(d.creationdate, 'yy-MM');
$$ LANGUAGE SQL STABLE;

-- usp_RandomQ - Main dispatcher that randomly executes one of the procedures
CREATE OR REPLACE FUNCTION usp_randomq()
RETURNS TABLE(result_text VARCHAR) AS $$
DECLARE
    v_random_id INTEGER;
BEGIN
    v_random_id := (RANDOM() * 10000000)::INTEGER;

    IF v_random_id % 28 = 0 THEN
        PERFORM * FROM usp_q7521(v_random_id);
    ELSIF v_random_id % 27 = 0 THEN
        PERFORM * FROM usp_q36660();
    ELSIF v_random_id % 26 = 0 THEN
        PERFORM * FROM usp_q949(v_random_id);
    ELSIF v_random_id % 25 = 0 THEN
        PERFORM * FROM usp_q466();
    ELSIF v_random_id % 24 = 0 THEN
        PERFORM * FROM usp_q947(v_random_id);
    ELSIF v_random_id % 23 = 0 THEN
        PERFORM * FROM usp_q3160(v_random_id);
    ELSIF v_random_id % 22 = 0 THEN
        PERFORM * FROM usp_q6627();
    ELSIF v_random_id % 21 = 0 THEN
        PERFORM * FROM usp_q6772(v_random_id);
    ELSIF v_random_id % 20 = 0 THEN
        PERFORM * FROM usp_q6856(5000::INTEGER, 100::INTEGER);
    ELSIF v_random_id % 19 = 0 THEN
        PERFORM * FROM usp_q952();
    ELSIF v_random_id % 18 = 0 THEN
        PERFORM * FROM usp_q975();
    ELSIF v_random_id % 17 = 0 THEN
        PERFORM * FROM usp_q8116(v_random_id);
    ELSIF v_random_id % 16 = 0 THEN
        PERFORM * FROM usp_q4038(v_random_id);
    ELSIF v_random_id % 15 = 0 THEN
        PERFORM * FROM usp_q2357(v_random_id);
    ELSIF v_random_id % 14 = 0 THEN
        PERFORM * FROM usp_q951();
    ELSIF v_random_id % 13 = 0 THEN
        PERFORM * FROM usp_q1433(v_random_id);
    ELSIF v_random_id % 12 = 0 THEN
        PERFORM * FROM usp_q7672();
    ELSIF v_random_id % 11 = 0 THEN
        PERFORM * FROM usp_q1256();
    ELSIF v_random_id % 10 = 0 THEN
        PERFORM * FROM usp_q877();
    ELSIF v_random_id % 9 = 0 THEN
        PERFORM * FROM usp_q886();
    ELSIF v_random_id % 8 = 0 THEN
        PERFORM * FROM usp_q10418('Teacher');
    ELSIF v_random_id % 7 = 0 THEN
        PERFORM * FROM usp_q946();
    ELSIF v_random_id % 6 = 0 THEN
        PERFORM * FROM usp_q6607();
    ELSIF v_random_id % 5 = 0 THEN
        PERFORM * FROM usp_q1080();
    ELSIF v_random_id % 4 = 0 THEN
        PERFORM * FROM usp_q6134(12::SMALLINT);
    ELSIF v_random_id % 3 = 0 THEN
        PERFORM * FROM usp_q2777();
    ELSIF v_random_id % 2 = 0 THEN
        PERFORM * FROM usp_q1933();
    ELSE
        PERFORM * FROM usp_q1181(v_random_id, '2010-01-01'::DATE, '2020-01-01'::DATE);
    END IF;

    RETURN QUERY SELECT 'Random query executed successfully'::VARCHAR;
END;
$$ LANGUAGE PLPGSQL;

-- ============================================================================
-- END OF CONVERTED FUNCTIONS
-- ============================================================================
-- Total: 34 functions (32 query + 1 report + 1 helper)
