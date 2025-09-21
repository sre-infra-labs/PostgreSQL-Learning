# pg_ctl is only accessible using postgres user
(base) saanvi@ryzen9:~/GitHub/PostgreSQL-Learning$ pg_ctl status
pg_ctl: could not open PID file "/var/lib/postgresql/16/main/postmaster.pid": Permission denied
(base) saanvi@ryzen9:~/GitHub/PostgreSQL-Learning$ 

# Switch to postgres user
(base) saanvi@ryzen9:~/GitHub/PostgreSQL-Learning$ 
(base) saanvi@ryzen9:~/GitHub/PostgreSQL-Learning$ sudo -i -u postgres
[sudo] password for saanvi: 
postgres@ryzen9:~$ pg_ctl status
Command 'pg_ctl' not found, did you mean:
  command 'dg_ctl' from deb drogon (1.8.7+ds-1)
Try: apt install <deb name>
postgres@ryzen9:~$

# Let's connect pgsql, and find PGDATA directory
(base) saanvi@ryzen9:~/GitHub/PostgreSQL-Learning$ which pg_ctl
/usr/lib/postgresql/16/bin/pg_ctl
(base) saanvi@ryzen9:~/GitHub/PostgreSQL-Learning$ psql -h localhost -U postgres -W
postgres_air=# show data_directory;
 /var/lib/postgresql/16/main
postgres_air=# show config_file;
 /etc/postgresql/16/main/postgresql.conf

# pg_ctl command not working. Need to set proper path
postgres@ryzen9:~$ nano ~/.bashrc

export PATH=$PATH:/usr/lib/postgresql/16/bin/
export PGDATA=/var/lib/postgresql/16/main/

postgres@ryzen9:~$ source ~/.bashrc
postgres@ryzen9:~$ pg_ctl status
pg_ctl: server is running (PID: 4922)
/usr/lib/postgresql/16/bin/postgres "-D" "/var/lib/postgresql/16/main" "-c" "config_file=/etc/postgresql/16/main/postgresql.conf"


# One line command to get postgres service status using pg_ctl
(base) saanvi@ryzen9:~/GitHub/PostgreSQL-Learning$ sudo -u postgres bash -c "source ~/.bashrc && pg_ctl status"
pg_ctl: server is running (PID: 505259)
/usr/lib/postgresql/16/bin/postgres "-D" "/var/lib/postgresql/16/main" "-c" "config_file=/etc/postgresql/16/main/postgresql.conf"
(base) saanvi@ryzen9:~/GitHub/PostgreSQL-Learning$ 

