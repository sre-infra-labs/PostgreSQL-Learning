DO $$
DECLARE
    v_random_post_id integer;
	v_user_id integer;
    v_random_voter_user_id integer;
    sql text;
BEGIN
    -- Step 1: Generate a random integer between 1 and 10000000
    v_random_post_id := FLOOR(RANDOM() * 10000000 + 1)::int;
    v_random_voter_user_id := FLOOR(RANDOM() * 10000000 + 1)::int;

	insert into votes (postid, votetypeid, userid, creationdate, bountyamount)
	select v_random_post_id, 1, v_random_voter_user_id, current_timestamp, null
	from posts p
	where p.id = v_random_post_id;

	update posts
		set score = score + 1
		where id = v_random_post_id
		returning owneruserid into v_user_id;

	update users
		set lastaccessdate = current_timestamp
		where id = v_random_voter_user_id;

	if v_user_id is not null then
		update users
			set reputation = reputation + 1
			where id = v_user_id;		
	end if;

END $$;