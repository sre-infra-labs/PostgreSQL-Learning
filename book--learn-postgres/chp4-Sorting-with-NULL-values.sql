/*
** Prerequisites **
-------------------

\c forumdb

insert into categories 
    (title) 
values ('A new discussion');

\pset null '(NULL)'

saanvi@localhost [10:30:36] (forumdb) 
=# \pselect * from categories order by description;
 pk |         title         |           description            
----+-----------------------+----------------------------------
  3 | Programming Languages | All about programming languages
  1 | Database              | Database related discussions
  4 | A.I                   | Machine Learning discussions
  5 | Software engineering  | Software engineering discussions
  2 | Unix                  | Unix and Linux discussions
  6 | A new discussion      | (NULL)
(6 rows)

saanvi@localhost [10:31:45] (forumdb) 
=# select * from categories order by description desc;
 pk |         title         |           description            
----+-----------------------+----------------------------------
  6 | A new discussion      | (NULL)
  2 | Unix                  | Unix and Linux discussions
  5 | Software engineering  | Software engineering discussions
  4 | A.I                   | Machine Learning discussions
  1 | Database              | Database related discussions
  3 | Programming Languages | All about programming languages
(6 rows)


--> With order Ascending, default NULL placement is at bottom
--> With order Descending, default NULL placement is at top

To control the NULL placement, using "NULLS <First|Last>"
*/

/*
saanvi@localhost [10:32:44] (forumdb) 
=#
*/ 
select * from categories order by description nulls first;
/*
 pk |         title         |           description            
----+-----------------------+----------------------------------
  6 | A new discussion      | (NULL)
  3 | Programming Languages | All about programming languages
  1 | Database              | Database related discussions
  4 | A.I                   | Machine Learning discussions
  5 | Software engineering  | Software engineering discussions
  2 | Unix                  | Unix and Linux discussions
(6 rows)

saanvi@localhost [10:33:00] (forumdb) 
=#
 
saanvi@localhost [10:33:36] (forumdb) 
=# 
*/
select * from categories order by description nulls last;
/*
 pk |         title         |           description            
----+-----------------------+----------------------------------
  3 | Programming Languages | All about programming languages
  1 | Database              | Database related discussions
  4 | A.I                   | Machine Learning discussions
  5 | Software engineering  | Software engineering discussions
  2 | Unix                  | Unix and Linux discussions
  6 | A new discussion      | (NULL)
(6 rows)
*/



