## Create temp postgresql cluster (execute all commands under postgres user)
```
ssh pgpoc

sudo su - postgres

sudo ls -l /usr/lib/postgresql/<version>/bin

# initialize database cluster
/usr/lib/postgresql/16/bin/initdb -D /tmp/pgsql

# start database cluster
/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgsql start
vim /tmp/pgsql/postgresql.conf
    change port -> 5431
or
/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgsql start -o "-p 5431"

    postgres@pgpoc:~$ /usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgsql start
    waiting for server to start....2025-09-06 19:58:10.476 IST [22310] LOG:  starting PostgreSQL 16.9 (Ubuntu 16.9-0ubuntu0.24.04.1) on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0, 64-bit
    2025-09-06 19:58:10.476 IST [22310] LOG:  listening on IPv4 address "127.0.0.1", port 5431
    2025-09-06 19:58:10.477 IST [22310] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5431"
    2025-09-06 19:58:10.482 IST [22313] LOG:  database system was shut down at 2025-09-06 19:57:15 IST
    2025-09-06 19:58:10.489 IST [22310] LOG:  database system is ready to accept connections
    done
    server started

# get port usage
sudo ss -ltn 'sport = :5432'
sudo lsof -i :5432

# connect to db cluster
postgres@pgpoc:~$ psql -p 5431
```

## Add extension
```
sudo su - postgres

vim /tmp/pgsql/postgresql.conf

    postgres@pgpoc:~$ cat /tmp/pgsql/postgresql.conf | grep -i shared_preload
    shared_preload_libraries = 'pg_stat_statements' # (change requires restart)

# restart database cluster
/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgsql restart

    postgres@pgpoc:~$ /usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgsql restart
    waiting for server to shut down...2025-09-06 20:05:25.988 IST [22310] LOG:  received fast shutdown request
    .2025-09-06 20:05:25.990 IST [22310] LOG:  aborting any active transactions
    2025-09-06 20:05:25.992 IST [22310] LOG:  background worker "logical replication launcher" (PID 22316) exited with exit code 1
    2025-09-06 20:05:25.993 IST [22311] LOG:  shutting down
    2025-09-06 20:05:25.994 IST [22311] LOG:  checkpoint starting: shutdown immediate
    2025-09-06 20:05:25.998 IST [22311] LOG:  checkpoint complete: wrote 0 buffers (0.0%); 0 WAL file(s) added, 0 removed, 0 recycled; write=0.001 s, sync=0.001 s, total=0.006 s; sync files=0, longest=0.000 s, average=0.000 s; distance=0 kB, estimate=236 kB; lsn=0/1535430, redo lsn=0/1535430
    2025-09-06 20:05:26.003 IST [22310] LOG:  database system is shut down
    done
    server stopped
    waiting for server to start....2025-09-06 20:05:26.115 IST [22373] LOG:  starting PostgreSQL 16.9 (Ubuntu 16.9-0ubuntu0.24.04.1) on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0, 64-bit
    2025-09-06 20:05:26.115 IST [22373] LOG:  listening on IPv4 address "127.0.0.1", port 5431
    2025-09-06 20:05:26.116 IST [22373] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5431"
    2025-09-06 20:05:26.120 IST [22376] LOG:  database system was shut down at 2025-09-06 20:05:25 IST
    2025-09-06 20:05:26.126 IST [22373] LOG:  database system is ready to accept connections
    done
    server started
    postgres@pgpoc:~$ 
```




