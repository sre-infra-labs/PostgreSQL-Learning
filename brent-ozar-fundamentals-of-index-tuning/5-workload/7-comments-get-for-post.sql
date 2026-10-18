DO $$
DECLARE
    v_random_id integer;
    sql text;
BEGIN
    -- Step 1: Generate a random integer between 1 and 10000000
    v_random_id := FLOOR(RANDOM() * 10000000 + 1)::int;

    -- Step 2: Build a SQL query
    sql := format('SELECT id, score, text, userdisplayname FROM comments WHERE postid = %s order by creationdate;', v_random_id);

    -- Step 3: Execute the query
    EXECUTE sql;
END $$;
