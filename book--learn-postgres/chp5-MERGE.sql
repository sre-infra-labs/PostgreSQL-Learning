/*  MERGE

Starting from PG 15, we have MERGE statement that helps achieve 2 transaction statements into one.



*/

-- Query 01
INSERT INTO categories (pk, title, description)
VALUES (n.pk, n.title, n.description)
ON CONFLICT (pk) -- Specify the unique constraint column
DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description;

-- Query 02
merge into categories c
using new_data n on c.pk = n.pk
when matched then
    update set title=n.title, description=n.description
when not matched then
    insert (pk, title, description)
    overriding system value
    values (n.pk, n.title, n.description);

