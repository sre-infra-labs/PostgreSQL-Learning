# Get postgres processes
(base) saanvi@ryzen9:/stale-storage/GitHub/PostgreSQL-Learning$ ps -C postgres -af
UID          PID    PPID  C STIME TTY          TIME CMD
postgres    1470       1  0 18:48 ?        00:00:00 /usr/lib/postgresql/16/bin/postgres -D /var/lib/postgresql/16/main -c config_file=/etc/postgresql/16/main/postgresql.conf
postgres    1864    1470  0 18:48 ?        00:00:00 postgres: 16/main: checkpointer 
postgres    1869    1470  0 18:48 ?        00:00:00 postgres: 16/main: background writer 
postgres    1945    1470  0 18:48 ?        00:00:00 postgres: 16/main: walwriter 
postgres    1950    1470  0 18:48 ?        00:00:00 postgres: 16/main: autovacuum launcher 
postgres    1953    1470  0 18:48 ?        00:00:00 postgres: 16/main: logical replication launcher 
postgres    9515    1470  0 18:49 ?        00:00:00 postgres: 16/main: postgres stackoverflow 192.168.1.2(58751) idle
postgres   11343    1470  0 18:49 ?        00:00:00 postgres: 16/main: ajay postgres 127.0.0.1(40124) idle
postgres   11345    1470  0 18:49 ?        00:00:00 postgres: 16/main: ajay postgres 127.0.0.1(40132) idle
postgres   11349    1470  0 18:49 ?        00:00:00 postgres: 16/main: ajay postgres 127.0.0.1(40148) idle
root      123244  117995  0 21:18 pts/5    00:00:00 sudo -u postgres psql
postgres  123289  123288  0 21:18 pts/6    00:00:00 /usr/lib/postgresql/16/bin/psql
postgres  123290    1470  0 21:18 ?        00:00:00 postgres: 16/main: postgres postgres [local] idle
saanvi    132993  115464  0 21:31 pts/4    00:00:00 ps -C postgres -af

