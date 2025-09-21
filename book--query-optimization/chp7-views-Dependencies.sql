/* Dependencies
**
** Both views and materialized views have queries associated with them, and
when any database object involved in those queries is altered, the dependent views and
materialized views need to be recreated.

Actually, PostgreSQL doesn’t even permit an alter or drop on a table or materialized
views if they have dependent views and materialized views. Making a change requires
adding the CASCADE keyword to the ALTER or DROP command.

Note
-----
Even if the column that is being dropped or altered does not participate in
any dependent object, the dependent objects still must be dropped and recreated.
Even adding a new column to the table will have a similar effect.

If views and materialized views are built on top of other views, adding one column
to one base table may result in recreating several dozen dependent database objects.

Creating a view does not take substantial time, but rebuilding multiple dependent
materialized views does, and all this time the materialized views will be unavailable,
even if they allow concurrent refreshes.
*/