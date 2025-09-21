/* Find existing Users */
SELECT 
    rolname AS role_name,
    rolsuper AS is_superuser,
    rolinherit AS can_inherit,
    rolcreaterole AS can_create_roles,
    rolcreatedb AS can_create_db,
    rolcanlogin AS can_login,
    rolreplication AS can_replication,
    rolbypassrls AS bypass_rls
FROM pg_roles
WHERE rolname not like 'pg_%' and rolname not in ('postgres')
ORDER BY rolname;


-- Create super user
create role ajay with login superuser password '<Password>';

-- make it admin on pg
alter role ajay with superuser;
GRANT ALL PRIVILEGES ON DATABASE stackoverflow TO ajay;

-- drop role
drop role ajay;

/* Identity objects owned by role */
SELECT 
    n.nspname AS schema_name,
    c.relname AS object_name,
    c.relkind AS object_type
FROM 
    pg_class c
JOIN 
    pg_namespace n ON n.oid = c.relnamespace
WHERE 
    c.relowner = (SELECT oid FROM pg_roles WHERE rolname = 'ajay');

SELECT 
    n.nspname AS schema_name,
    p.proname AS function_name
FROM 
    pg_proc p
JOIN 
    pg_namespace n ON n.oid = p.pronamespace
WHERE 
    p.proowner = (SELECT oid FROM pg_roles WHERE rolname = 'ajay');

SELECT 
    n.nspname AS schema_name
FROM 
    pg_namespace n
WHERE 
    n.nspowner = (SELECT oid FROM pg_roles WHERE rolname = 'ajay');


/* Resolve ownership */
REASSIGN OWNED BY ajay TO postgres;

/* Terminate existing connections */
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.usename = 'ajay';




# Add entry in pg_hba.conf file also

-- Change password
alter user postgres password '<Password>';


/* Add entry for these users in pg_hba (/etc/postgres/16/main/pg_hba.conf) */
# ************************** Custom Settings by DBA ****************************************

# "local" is for Unix domain socket connections only
local   all     all                     peer

# Allow localhost tcp connections for postgres with password 
host    all             postgres    127.0.0.1/32    scram-sha-256
host    all             postgres    ::1/128         scram-sha-256

# Allow local network tcp connections for postgres with password
host    all             postgres    192.168.0.0/16    scram-sha-256

# Reject all not local tcp connections for postgres role
host    all             postgres    0.0.0.0/0           reject
host    all             postgres    ::/0                reject

# Allow local network tcp connections using password for all roles
host    all             all         0.0.0.0/0           scram-sha-256
host    all             all         ::/0                scram-sha-256


/* Restart PG Service */
systemctl status postgresql@16-main.service
OR
systemctl status postgresql.service


/* Query to view Parsed Rules */
SELECT 
    line_number,
    type,
    database,
    user_name AS role,
    address,
    auth_method
FROM 
    pg_hba_file_rules
WHERE 
    user_name = 'ajay' OR user_name IS NULL -- Rules for 'ajay' or all users
ORDER BY 
    line_number;


/* Test Rules */
-- peer authentication
psql -d postgres

-- remote with password
psql -h localhost -U ajay -d postgres --password

-- peer authentication using another login
    -- connect to local postgresql with peer authentication of postgres login
sudo -u postgres psql

-- switch to postgres user via sudo
sudo su - postgres
psql

-- start a full login shell as postgres user
sudo -i -u postgres
psql

-- once adwivedi is added in /etc/sudoers using visudo as mentioned below
    -- connect with peer authentication
su - adwivedi
psql


/*  Allow adwivedi to Impersonate postgres user without password
    Allow saanvi to Impersonate adwivedi user without password
*/
sudo visudo

    adwivedi ALL=(postgres) NOPASSWD:ALL
    saanvi ALL=(adwivedi) NOPASSWD:ALL

-- Verify the changes
sudo -l -U adwivedi
sudo -l -U saanvi

