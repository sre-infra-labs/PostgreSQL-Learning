# PostgreSQL-Learning
This repo contains scripts created while learning PostgreSQL

- Good knowledge of PostgreSQL Database Architecture.
- Installing, configuring PostgreSQL using source code, RPM, one-click installation on-prem and Cloud Technologies.
- Strong experience in handling Database Logical and Physical Backups.
- Expertise in Applying database patches from lower version to higher version.
- Implemented PostgreSQL DR servers and PostgreSQL load balancing using pgpool.
- Expertise in Streaming Replication (Including Cascading Replication).
- Configuring pgbouncer for connection pooling.

# Links

- [Using Apache Kafka to Replicate Data from PostgreSQL to Microsoft SQL Server](https://minervadb.xyz/using-kafka-to-replicate-data/)


# Install PostgreSQL from PGDG on Redhat Family

```bash
# Automated PGDG Repo Configuration on Ubuntu
  # This helps avoid default Postgres provided by Ubuntu
sudo apt install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh

# check what got installed
sudo apt list --installed postgres*

# update system
sudo apt update -y
sudo apt upgrade -y

# Install postgres
sudo apt install postgresql-18

# check what got installed
sudo apt list --installed postgres*

    Listing... Done
    postgresql-18-jit/noble-pgdg,now 18.6-1.pgdg24.04+2 amd64 [installed,automatic]
    postgresql-18/noble-pgdg,now 18.6-1.pgdg24.04+2 amd64 [installed]
    postgresql-client-18/noble-pgdg,now 18.6-1.pgdg24.04+2 amd64 [installed,automatic]
    postgresql-client-common/noble-pgdg,now 293.pgdg24.04+1 all [installed,automatic]
    postgresql-common/noble-pgdg,now 293.pgdg24.04+1 all [installed]

# check postgres service
sudo systemctl status postgresql@18-main

    ● postgresql@18-main.service - PostgreSQL Cluster 18-main
        Loaded: loaded (/usr/lib/systemd/system/postgresql@.service; enabled-runtime; preset: enabled)
        Active: active (running) since Mon 2026-11-02 00:26:21 UTC; 1min 19s ago
        Process: 11874 ExecStart=/usr/bin/pg_ctlcluster --skip-systemctl-redirect 18-main start (code=exited, status=0/SUCCESS)
      Main PID: 11879 (postgres)
          Tasks: 9 (limit: 4600)
        Memory: 25.1M (peak: 32.4M)
            CPU: 169ms
        CGroup: /system.slice/system-postgresql.slice/postgresql@18-main.service
                ├─11879 /usr/lib/postgresql/18/bin/postgres -D /var/lib/postgresql/18/main -c config_file=/etc/postgresql/18/main/postgresql.conf
                ├─11880 "postgres: 18/main: io worker 1"
                ├─11881 "postgres: 18/main: io worker 0"
                ├─11882 "postgres: 18/main: io worker 2"
                ├─11883 "postgres: 18/main: checkpointer "
                ├─11884 "postgres: 18/main: background writer "
                ├─11886 "postgres: 18/main: walwriter "
                ├─11887 "postgres: 18/main: autovacuum launcher "
                └─11888 "postgres: 18/main: logical replication launcher "

    Nov 02 00:26:18 sqlbuntu systemd[1]: Starting postgresql@18-main.service - PostgreSQL Cluster 18-main...
    Nov 02 00:26:21 sqlbuntu systemd[1]: Started postgresql@18-main.service - PostgreSQL Cluster 18-main.


# switch to postgres user
sudo su - postgres

# Edit /etc/postgresql/18/main/postgresql.conf
listen_addresses = '*'

# Edit /etc/postgresql/18/main/pg_hba.conf
host    all             all             192.168.0.0/16          scram-sha-256

# Reload conf
psql -c "select pg_reload_conf();"

# Exit postgres user
exit

# Create *.pgpass file
cat <<'EOF' > ~/.pgpass
#hostname:port:database:username:password
*:*:*:saanvi:SomeSuperStrongPasswordHere
EOF

# test postgresql connectivity under saanvi
psql -d postgres
```


### Any find over 2 MB in size within current repo
```
find . -type f -size +2M -exec ls -lh {} \;
```