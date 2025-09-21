/*  Common Table Expressions (CTE)
    
Starting with PG 12, two new options has been added
    - MATERIALIZED
    - NOT MATERIALIZED

By default, if the CTE is used only ones, then engine tried to perform "in place" operation.

If the CTE is used more than ones in same statement, then it is materialized to disk before getting used.

CTE Use Cases
-------------

-- Delete & Insert into same transaction using CTE
with del_posts as (
    delete from t_posts
    where category in (select pk from categories where title = 'Database Discussions')
    returning *
)
insert into delete_posts
select * from del_posts;


-- Insert & Delete into same transaction using CTE
with ins_posts as (
    insert into inserted_posts
    select * from t_posts
    returning *
)
delete from t_posts
where pk in (select pk from ins_posts);


Recursive CTE
----------------

A recursive CTE is a special construct that allows an auxiliary statement to reference itself
and, therefore, join itself onto previously computed results.
This is particularly useful when we need to join a table an unknown number of times, typically
to "explode" a flat tree structure.



*/

-- Analyze the raw data
select * from tags;
/*
 pk |        tag        | parent 
----+-------------------+--------
  1 | Operating Systems |       
  2 | Linux             |      1
  3 | Ubuntu            |      2
  4 | Kubuntu           |      3
  5 | Database          |       
  6 | Operating Systems |       
*/

with recursive tags_tree as (
    -- non recursive statement
    select tag, pk, 1 as level
    from tags
    where parent is null
    --
    union
    --
    -- recursive statement
    select tt.tag || ' -> ' || ct.tag, ct.pk, tt.level + 1
    from tags ct
    join tags_tree tt
      on tt.pk = ct.parent
)
select level, tag
from tags_tree;

/*
 level |                       tag                       
-------+-------------------------------------------------
     1 | Operating Systems
     1 | Database
     1 | Operating Systems
     2 | Operating Systems -> Linux
     3 | Operating Systems -> Linux -> Ubuntu
     4 | Operating Systems -> Linux -> Ubuntu -> Kubuntu
*/