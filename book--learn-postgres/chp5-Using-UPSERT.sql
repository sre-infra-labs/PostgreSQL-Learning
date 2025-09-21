/*
\c forumdb

saanvi@localhost [12:59:59] (forumdb) 
=# \d j_posts_tags
             Table "forum.j_posts_tags"
 Column  |  Type   | Collation | Nullable | Default 
---------+---------+-----------+----------+---------
 tag_pk  | integer |           | not null | 
 post_pk | integer |           | not null | 
Indexes:
    "j_posts_tags_pkey" PRIMARY KEY, btree (tag_pk, post_pk)
Foreign-key constraints:
    "j_posts_tags_post_pk_fkey" FOREIGN KEY (post_pk) REFERENCES posts(pk)
    "j_posts_tags_tag_pk_fkey" FOREIGN KEY (tag_pk) REFERENCES tags(pk)


*/

-- insert first time
insert into j_posts_tags (post_pk, tag_pk)
values (3,2), (5,1), (6,1);

-- Insert another time
insert into j_posts_tags (post_pk, tag_pk)
values (6,1);

-- Upsert
insert into j_posts_tags (post_pk, tag_pk)
values (6,1)
on conflict (post_pk, tag_pk)
    --do nothing;
    do update set tag_pk = excluded.tag_pk+1;

-- check data
select *
from j_posts_tags
where post_pk = 6;

-- Returning Clause for INSERT
insert into j_posts_tags (post_pk, tag_pk)
values (6,5)
returning *;

insert into j_posts_tags (post_pk, tag_pk)
values (6,5)
returning tag_pk, post_pk;
