/*
\du -> describe user
\drg -> show all groups a role is member of
*/

select r.rolname, r.rolsuper, r.rolinherit, r.rolcanlogin, r.rolconnlimit,
        r.rolvaliduntil, r.rolbypassrls, r.oid, a.rolpassword
from pg_roles r
inner join pg_authid a
    on a.rolname = r.rolname
where r.rolcanlogin is True;