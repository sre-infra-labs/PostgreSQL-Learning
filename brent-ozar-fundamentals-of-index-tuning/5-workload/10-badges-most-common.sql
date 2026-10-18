DO $$
DECLARE
    sql text;
BEGIN
    -- Step 1: Build a SQL query
    sql := format('SELECT name, count(*) as badges_earned FROM badges group by name order by count(*) desc, name LIMIT 100;');

    -- Step 2: Execute the query
    EXECUTE sql;
END $$;
