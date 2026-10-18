DO $$
DECLARE
    v_random_post_id integer;
    v_random_viewer_user_id integer;
    sql text;
BEGIN
    -- Step 1: Generate a random integer between 1 and 10000000
    v_random_post_id := FLOOR(RANDOM() * 10000000 + 1)::int;
    v_random_viewer_user_id := FLOOR(RANDOM() * 10000000 + 1)::int;

	update posts
		set viewcount = viewcount + 1
		where id = v_random_post_id;

	update users
		set lastaccessdate = current_timestamp
		where id = v_random_viewer_user_id;

END $$;