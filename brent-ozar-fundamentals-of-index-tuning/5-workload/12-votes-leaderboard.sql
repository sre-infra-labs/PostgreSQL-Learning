DO $$
DECLARE
    sql text;
BEGIN
    -- Step 1: Build a SQL query
    sql := format('SELECT postid, count(*) as votes_tallied FROM votes WHERE votetypeid = 1 group by postid order by count(*) desc LIMIT 100;');

    -- Step 2: Execute the query
    EXECUTE sql;
END $$;
