drop table if exists myusers;
create table if not exists myusers (
    id int generated ALWAYS as IDENTITY,
    username text not null,
    email text not null,
    primary key (id),
    unique(username)
);

drop table if exists temp_posts;
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
create temp table temp_posts as
    select * from public.posts;
/*
Seq Scan on public.posts  (cost=0.00..383414.79 rows=3673479 width=816) (actual time=0.467..2528.087 rows=3680688 loops=1)
  Output: id, posttypeid, acceptedanswerid, parentid, creationdate, deletiondate, score, viewcount, body, owneruserid, ownerdisplayname, lasteditoruserid, lasteditordisplayname, lasteditdate, lastactivitydate, title, tags, answercount, commentcount, favoritecount, closeddate, communityowneddate, contentlicense
  Buffers: shared read=346680
Planning Time: 0.461 ms
Execution Time: 4785.761 ms
*/

drop table temp2_posts;
EXPLAIN (ANALYZE, TIMING, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
create UNLOGGED table temp2_posts as
    select * from public.posts;
/*
Seq Scan on public.posts  (cost=0.00..383414.79 rows=3673479 width=816) (actual time=2.071..2485.866 rows=3680688 loops=1)
  Output: id, posttypeid, acceptedanswerid, parentid, creationdate, deletiondate, score, viewcount, body, owneruserid, ownerdisplayname, lasteditoruserid, lasteditordisplayname, lasteditdate, lastactivitydate, title, tags, answercount, commentcount, favoritecount, closeddate, communityowneddate, contentlicense
  Buffers: shared read=346680
Planning Time: 0.034 ms
Execution Time: 4996.795 ms
*/