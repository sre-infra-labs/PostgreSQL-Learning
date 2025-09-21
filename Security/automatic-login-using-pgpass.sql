-- Use .pgpass file
~/.pgpass
chmod 600 ~/.pgpass

localhost:*:*:username:password
ryzen9:*:*:username:password
*:*:*:username:password

# hostname:port:database:username:password
# psql 'postgresql://username:password@hostname:port/database'
# pg_restore --dbname='postgresql://username:password@hostname:port/database' [options] dumpfile


-- Configure .pg_service.conf (Optional for Simplified Connection)
nano ~/.pg_service.conf
    -------------------------------
    [rds-postgres-01]
    host=rds-postgres-01.......rds.amazonaws.com
    port=5432
    dbname=postgres
    user=postgres
    password=MyStrongPassword
    -----------------------------

-- Set env variable
export PGSERVICEFILE=~/.pg_service.conf

-- connect using service
psql service=rds-postgres-01





