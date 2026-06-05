# [Convert a Standalone to a Patroni Cluster on Ubuntu](https://patroni.readthedocs.io/en/latest/existing_data.html)

```
(base) ----- [2026-Jun-05 08:37:17] saanvi@ryzen9 (PostgreSQL-Learning)
|------------$ systemctl status postgresql@16-main.service 
● postgresql@16-main.service - PostgreSQL Cluster 16-main
     Loaded: loaded (/usr/lib/systemd/system/postgresql@.service; enabled-runtime; preset: enabled)
     Active: active (running) since Fri 2026-06-05 08:20:19 IST; 1h 26min ago
    Process: 4774 ExecStart=/usr/bin/pg_ctlcluster --skip-systemctl-redirect 16-main start (code=exited, status=0/SUCCESS)
   Main PID: 5149 (postgres)
      Tasks: 8 (limit: 154371)
     Memory: 312.1M (peak: 317.4M)
        CPU: 5.759s
     CGroup: /system.slice/system-postgresql.slice/postgresql@16-main.service
             ├─ 5149 /usr/lib/postgresql/16/bin/postgres -D /var/lib/postgresql/16/main -c config_file=/etc/postgresql/16/main/postgresql.conf
             ├─ 5887 "postgres: 16/main: logger "
             ├─ 6189 "postgres: 16/main: checkpointer "
             ├─ 6191 "postgres: 16/main: background writer "
             ├─ 6241 "postgres: 16/main: walwriter "
             ├─ 6243 "postgres: 16/main: autovacuum launcher "
             ├─ 6245 "postgres: 16/main: logical replication launcher "
             └─37787 "postgres: 16/main: postgres postgres 127.0.0.1(48374) idle"

Jun 05 08:20:16 ryzen9 systemd[1]: Starting postgresql@16-main.service - PostgreSQL Cluster 16-main...
Jun 05 08:20:19 ryzen9 systemd[1]: Started postgresql@16-main.service - PostgreSQL Cluster 16-main.
```


