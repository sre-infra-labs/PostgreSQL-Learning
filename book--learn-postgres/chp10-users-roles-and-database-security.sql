
/*

Understanding Roles
----------------------------

-> A role id identifier used to connect to postgresql cluster.
-> An option can be added to a role in positive or negative form.
-> A negative form would have "NO" prefix on its positive form.
    -> NOCREATEROLE
    -> NOCREATEDB
    -> NOLOGIN
-> CREATE/ALTER ROLE can be executed by SUPERUSER or user with CREATEROLE permissions.

CREATE ROLE <name> [ [WITH] option [ ... ] ]
ALTER ROLE <name> [ [WITH] option] [ ... ] ]

-> "=>" is prompt for a regular user
-> "=#" is prompt for an administrator user
-> SUPERUSER option to a role makes cluster administrator
-> REPLICATION property enables a role to use the replication protocol

Example -

-- create user
create role luca with nocreatedb login;
-- alter user
alter role luca with createrole createdb;
-- rename user
alter role luca rename to fluca1978;

Row Level Security (RLS)
-------------------------------------

-> RLS mechanism helps restrict access to certain set of rows in tables
-> RLS:BYPASSRLS & RLS:NOBYPASSRLS can be used to set the option
-> SUPERUSER roles are always able to bypass RLS policies


SESSION_USER vs CURRENT_USER vs CURRENT_ROLE
--------------------------------------------

-> SESSION_USER is the role that opened the connection to cluster
-> CURRENT_USER is the effective role set using SET ROLE statement
-> CURRENT_ROLE is same as CURRENT_USER.

=> sudo -u postgres psql
psql
----
postgres=> select current_user, session_user;
postgres=> set role saanvi;
postgres=> select current_user, session_user;


Per-Role Configuration Parameters
-----------------------------------

-> It is possible to setup Specific configuration settings to a role

ALTER ROLE <name> IN DATABASE <dbname> SET <parameter_name> TO <parameter_value>;

Example -
--------------------
$ psql -U luca forumdb
forumdb=> set client_min_messages to 'DEBUG';

forumdb=# alter role luca in database forumdb set client_min_messages to 'DEBUG';

$ psql -U luca forumdb
forumdb=> show client_min_messages;
--------------------

-> To reset all configuration parameters for a ROLE

forumdb=# ALTER ROLE luca IN DATABASE forumdb RESET ALL;


Inspecting Roles
---------------------------

-> To list roles in psql
forumdb=# \du+

-> To get rules using sql query
forumdb=# select * from pg_authid where rolname = 'forum';
forumdb=> select * from pg_roles where rolname = 'forum';

-> To get group membership
forumdb=# 
select r.rolname, g.rolname as group, m.admin_option as is_admin
from pg_auth_members m
join pg_roles r on r.oid = m.member
join pg_roles g on g.oid = m.roleid
order by r.rolname;


Roles Inheritance
------------------------


forumdb=# 
create role forum_admins with nologin;
create role forum_stats with nologin;

revoke all on forum.users from forum_stats;
revoke all on forum.users from forum_admins;

grant all on schema forum to forum_admins;
grant usage on schema forum to forum_stats;
grant all on forum.users to forum_admins;
grant select (username, gecos) on forum.users to forum_stats;

grant forum_admins to enrico;
grant forum_stats to luca;






*/







