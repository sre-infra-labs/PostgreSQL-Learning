# Convert a Standalone to a Patroni Cluster — docker Containers

Host (container runtime) — ryzen9 (192.168.100.1), Ubuntu 24.04
docker network        — lab-network (172.18.0.0/16)
Patroni cluster name  — docpg-cls2
pgbackrest stanza     — docpg-cls2
pgbackrest backup     — Docker named volume pg-backups → /var/lib/pgbackrest inside each container

| Container        | IP           | SSH (host) | PG (host) | Patroni (host) |
|------------------|--------------|------------|-----------|----------------|
| docpg-cls2-pg1   | 172.18.0.21  | 2231       | 5441      | 8021           |
| docpg-cls2-pg2   | 172.18.0.22  | 2232       | 5442      | 8022           |
| docpg-cls2-pg3   | 172.18.0.23  | 2233       | 5443      | 8023           |
| docpg-cls2-pg4   | 172.18.0.24  | 2234       | 5444      | 8024           |

# Tools
- postgresql 18 (PGDG apt)
- patroni latest (pip)
- pgbackrest latest (apt)
- etcd v3.5.17 (binary)


---

# Part 1 — Create the docker Container (docpg-cls2-pg1)

> Run all commands on **ryzen9** (the docker host) unless noted otherwise.

## 1. Build the base image (skip if `pg-cluster-node:latest` already exists)

```bash
# The Dockerfile is in the cls1 playbook directory — reuse it for cls2
cd playbook-convert-standalone-2-patroni-cluster/

docker build -t pg-cluster-node:latest .

# Verify
docker image ls pg-cluster-node:latest
```

## 2. Create a shared named volume for pgBackRest backups

> We use a shared Docker named volume for backups so all containers can access the same repository.

```bash
docker volume create pg-backups

# Verify
docker volume ls | grep pg-backups
```

## 3. Create a named volume for PostgreSQL data

```bash
docker volume create pg-cls2-data-pg1
docker volume create pg-cls2-logs-pg1

# Verify
docker volume ls | grep pg-cls2
```

## 4. Create the container

```bash
docker run -d \
  --name docpg-cls2-pg1 \
  --hostname docpg-cls2-pg1 \
  --network lab-network:ip=172.18.0.21 \
  --privileged \
  --cgroupns=host \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  --tmpfs /run \
  --tmpfs /run/lock \
  --volume pg-cls2-data-pg1:/var/lib/postgresql \
  --volume pg-cls2-logs-pg1:/var/log \
  --volume pg-backups:/var/lib/pgbackrest \
  --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --restart=unless-stopped \
  pg-cluster-node:latest

# Verify it is running
docker ps --filter name=docpg-cls2-pg1
```

## 5. Open a shell inside the container

```bash
docker exec -it docpg-cls2-pg1 bash
# All subsequent commands in Parts 2–5 run INSIDE this shell unless noted.
```

## 5. Add /etc/hosts entries (skip own IP)

```bash
# Run inside docpg-cls2-pg1
cat >> /etc/hosts << 'EOF'
172.18.0.22     docpg-cls2-pg2
172.18.0.23     docpg-cls2-pg3
172.18.0.24     docpg-cls2-pg4
172.18.0.25     docpg-cls2-pg5
172.18.0.26     docpg-cls2-pg6
EOF
```

---

# Part 2 — Install PostgreSQL 18

> Run inside **docpg-cls2-pg1**.

## 1. Add PGDG apt repository

```bash
apt-get update
apt-get install -y curl ca-certificates gnupg2 lsb-release

install -d /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc

echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
  https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list

apt-get update
```

## 2. Install PostgreSQL 18 and pgbackrest

```bash
apt-get install -y \
  postgresql-18 \
  postgresql-client-18 \
  postgresql-contrib-18 \
  postgresql-server-dev-18 \
  pgbackrest \
  python3 python3-pip python3-dev \
  gcc curl wget jq acl less

# Verify
/usr/lib/postgresql/18/bin/postgres --version
pgbackrest version
```

## 3. Set up postgres user home and profile

```bash
# Clear any previous installation
pg_dropcluster --stop 18 main 2>/dev/null || true

# postgres user and /var/lib/postgresql already exist from the package install
mkdir -p /var/lib/postgresql/{18/main,log,scripts}
chown -R postgres:postgres /var/lib/postgresql

sudo -u postgres tee /var/lib/postgresql/.bash_profile > /dev/null << 'EOF'
# PostgreSQL 18 environment
export PATH=/usr/lib/postgresql/18/bin:$PATH
export PGDATA=/var/lib/postgresql/18/main
export PGPORT=5432
export PGPASSFILE=/var/lib/postgresql/.pgpass
export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
EOF
```

## 4. Drop the apt auto-created cluster; run initdb manually

```bash
# Stop and drop the default cluster created by the apt package
pg_dropcluster --stop 18 main 2>/dev/null || true
rm -rf /var/lib/postgresql/18/main/*

# initdb — configs go into the data dir (consistent with Patroni's expectations)
sudo -u postgres /usr/lib/postgresql/18/bin/initdb \
  --encoding=UTF8 \
  --data-checksums \
  --pgdata=/var/lib/postgresql/18/main \
  --auth-local=peer \
  --auth-host=scram-sha-256

ls /var/lib/postgresql/18/main/
```

## 5. Configure postgresql.conf

```bash
sudo -u postgres tee -a /var/lib/postgresql/18/main/postgresql.conf > /dev/null << 'EOF'

#---------------------------------------------------------------------------
# PATRONI / REPLICATION SETTINGS (appended by this guide)
#---------------------------------------------------------------------------
listen_addresses = '*'
port = 5432
max_connections = 200

# WAL / replication
wal_level = replica
hot_standby = on
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 4GB

# Archive (pgbackrest)
archive_mode = on
archive_command = 'pgbackrest --stanza=docpg-cls2 archive-push %p'
restore_command = 'pgbackrest --stanza=docpg-cls2 archive-get %f %p'

# Logging
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_connections = on
log_disconnections = on
log_checkpoints = on
log_lock_waits = on
log_min_duration_statement = 5000

# Performance
shared_buffers = 256MB
effective_cache_size = 768MB
checkpoint_timeout = 30
EOF
```

## 6. Configure pg_hba.conf

```bash
sudo -u postgres tee /var/lib/postgresql/18/main/pg_hba.conf > /dev/null << 'EOF'
# TYPE  DATABASE        USER            ADDRESS                  METHOD
local   all             postgres                                 peer
local   all             all                                      scram-sha-256

# IPv4 / IPv6 loopback
host    all             all              127.0.0.1/32            scram-sha-256
host    all             all              ::1/128                 scram-sha-256

# Streaming replication — cluster subnet
host    replication     replicator       127.0.0.1/32            scram-sha-256
host    replication     replicator       ::1/128                 scram-sha-256
host    replication     replicator       172.18.0.0/24           scram-sha-256

# pg_rewind
host    all             replicator       127.0.0.1/32            scram-sha-256
host    all             replicator       ::1/128                 scram-sha-256
host    all             replicator       172.18.0.0/24           scram-sha-256

# Application connections
host    all             all              172.18.0.0/24           scram-sha-256
host    all             all              192.168.100.0/24        scram-sha-256
EOF
```

## 7. Create .pgpass

```bash
sudo -u postgres tee /var/lib/postgresql/.pgpass > /dev/null << 'EOF'
*:*:*:postgres:YourSuperUserPassword
*:5432:*:replicator:YourReplicatorPassword
EOF

chmod 0750 -R /var/lib/postgresql
chmod 0600 /var/lib/postgresql/.pgpass
```

## 8. Create a systemd service and start PostgreSQL (standalone)

```bash
tee /etc/systemd/system/postgresql-18.service > /dev/null << 'EOF'
[Unit]
Description=PostgreSQL 18 Database Server
After=network.target

[Service]
Type=forking
User=postgres
Group=postgres
Environment=PGDATA=/var/lib/postgresql/18/main
ExecStart=/usr/lib/postgresql/18/bin/pg_ctl start \
  -D /var/lib/postgresql/18/main \
  -l /var/log/postgresql/startup.log
ExecStop=/usr/lib/postgresql/18/bin/pg_ctl stop \
  -D /var/lib/postgresql/18/main
ExecReload=/usr/lib/postgresql/18/bin/pg_ctl reload \
  -D /var/lib/postgresql/18/main
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable postgresql-18
systemctl start postgresql-18
systemctl status postgresql-18
```

## 9. Create replication roles and set passwords

```bash
sudo -u postgres psql << 'EOF'
CREATE ROLE replicator WITH LOGIN REPLICATION BYPASSRLS ENCRYPTED PASSWORD 'YourReplicatorPassword';
ALTER  ROLE postgres   WITH LOGIN SUPERUSER REPLICATION BYPASSRLS ENCRYPTED PASSWORD 'YourSuperUserPassword';
\du
EOF
```

---

# Part 3 — Configure pgbackrest (Docker Named Volume)

> Run inside **docpg-cls2-pg1**.
> The Docker named volume `pg-backups` is mounted
> into every container at `/var/lib/pgbackrest` via the `--volume` flag at container creation.

## 1. Verify the volume mount is active

```bash
# Should show the backup directory contents (if any)
ls -la /var/lib/pgbackrest

# Ensure postgres owns the directory
chown postgres:postgres /var/lib/pgbackrest

# Verify postgres can write and delete
sudo -u postgres bash -c 'touch /var/lib/pgbackrest/test && echo "Write OK" && rm /var/lib/pgbackrest/test && echo "Delete OK"'
```

## 2. Configure pgbackrest.conf

```bash
mkdir -p /etc/pgbackrest

tee /etc/pgbackrest/pgbackrest.conf > /dev/null << 'EOF'
[global]
# Docker named volume mounted into the container at /var/lib/pgbackrest
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
repo1-retention-diff=7
log-level-console=info
log-level-file=detail
log-path=/var/log/pgbackrest

process-max=4
compress-type=lz4
compress-level=3

archive-async=y
spool-path=/var/spool/pgbackrest
archive-queue-max=268435456
archive-timeout=1800

[docpg-cls2]
pg1-path=/var/lib/postgresql/18/main
pg1-port=5432
pg1-user=postgres
EOF

chmod 755 /etc/pgbackrest/
chmod 644 /etc/pgbackrest/pgbackrest.conf

# Required directories
mkdir -p /var/log/pgbackrest /var/spool/pgbackrest
chown postgres:postgres /var/log/pgbackrest /var/spool/pgbackrest
```

## 3. Create the stanza and take the initial backup

```bash
sudo -i -u postgres bash << 'EOF'
# Stanza-create initialises the repository directory structure
pgbackrest --stanza=docpg-cls2 stanza-create

# End-to-end config check
pgbackrest --stanza=docpg-cls2 check

# First full backup
pgbackrest --stanza=docpg-cls2 --type=full backup

# Confirm
pgbackrest --stanza=docpg-cls2 info
EOF
```

---

# Part 4 — Convert Standalone to Patroni (Single Node)

> Run inside **docpg-cls2-pg1**.

## 1. Install etcd (binary)

```bash
ETCD_VER=v3.6.12

curl -L \
  https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz \
  -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz

tar -xzf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /usr/local/bin/ \
  --strip-components=1 \
  etcd-${ETCD_VER}-linux-amd64/etcd \
  etcd-${ETCD_VER}-linux-amd64/etcdctl

etcd --version
etcdctl version
```

## 2. Install Patroni

```bash
pip3 install "patroni[etcd3]" "psycopg[binary]" --break-system-packages

# Add /usr/local/bin to PATH system-wide
echo 'export PATH=/usr/local/bin:$PATH' > /etc/profile.d/local-bin.sh
chmod 644 /etc/profile.d/local-bin.sh
export PATH=/usr/local/bin:$PATH

patroni --version
patronictl version
python3 -c "import psycopg; print(psycopg.__version__)"
```

## 3. Configure etcd (single-node bootstrap)

```bash
useradd --system --no-create-home --shell /sbin/nologin etcd 2>/dev/null || true

mkdir -p /etc/etcd /var/lib/etcd

tee /etc/etcd/etcd.conf > /dev/null << 'EOF'
ETCD_NAME="docpg-cls2-pg1"
ETCD_DATA_DIR="/var/lib/etcd"

ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://172.18.0.21:2379"

ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://172.18.0.21:2380"

ETCD_INITIAL_CLUSTER="docpg-cls2-pg1=http://172.18.0.21:2380"
ETCD_INITIAL_CLUSTER_TOKEN="docpg-cls2-etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF

chown -R etcd:etcd /etc/etcd/ /var/lib/etcd/
chmod 0755 /etc/etcd/ /var/lib/etcd/
chmod 0644 /etc/etcd/etcd.conf

tee /etc/systemd/system/etcd.service > /dev/null << 'EOF'
[Unit]
Description=etcd distributed key-value store
After=network.target

[Service]
Type=notify
User=etcd
Group=etcd
EnvironmentFile=/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now etcd
systemctl status etcd

etcdctl --endpoints=http://172.18.0.21:2379 endpoint health
```

## 4. Configure Patroni

```bash
mkdir -p /etc/patroni

tee /etc/patroni/patroni.yml > /dev/null << 'EOF'
scope: docpg-cls2
namespace: /db/
name: docpg-cls2-pg1

restapi:
  listen: 172.18.0.21:8008
  connect_address: 172.18.0.21:8008

etcd3:
  hosts: 172.18.0.21:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        wal_keep_size: 1GB
        max_wal_senders: 10
        max_replication_slots: 10
        checkpoint_timeout: 30
        archive_mode: "on"
        archive_command: "pgbackrest --stanza=docpg-cls2 archive-push %p"
        restore_command: "pgbackrest --stanza=docpg-cls2 archive-get %f %p"

  slots:
    standby_cluster_slot:
      type: physical

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - "local   all             postgres                            peer"
    - "local   all             all                                 scram-sha-256"
    - "host    all             all             127.0.0.1/32        scram-sha-256"
    - "host    all             all             ::1/128             scram-sha-256"
    - "host    replication     replicator      127.0.0.1/32        scram-sha-256"
    - "host    replication     replicator      ::1/128             scram-sha-256"
    - "host    replication     replicator      172.18.0.0/24       scram-sha-256"
    - "host    all             all             172.18.0.0/24       scram-sha-256"
    - "host    all             all             192.168.100.0/24    scram-sha-256"

postgresql:
  listen: "0.0.0.0:5432"
  connect_address: "172.18.0.21:5432"
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/lib/postgresql/18/bin
  config_dir: /var/lib/postgresql/18/main
  pgpass: /var/lib/postgresql/.pgpass_patroni
  authentication:
    replication:
      username: replicator
      password: YourReplicatorPassword
    superuser:
      username: postgres
      password: YourSuperUserPassword
    rewind:
      username: postgres
      password: YourSuperUserPassword
  parameters:
    unix_socket_directories: "/var/run/postgresql,/tmp"
    log_directory: /var/log/postgresql
    log_filename: "postgresql-%Y-%m-%d_%H%M%S.log"
    logging_collector: "on"
    shared_buffers: 256MB

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

chown postgres:postgres /etc/patroni/ /etc/patroni/patroni.yml
chmod 0755 /etc/patroni/
chmod 0600 /etc/patroni/patroni.yml
```

## 5. Create Patroni systemd service

```bash
tee /etc/systemd/system/patroni.service > /dev/null << 'EOF'
[Unit]
Description=Patroni — High Availability PostgreSQL Cluster Manager
After=syslog.target network.target etcd.service
Wants=etcd.service

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
ExecReload=/bin/kill -s HUP $MAINPID
KillMode=process
TimeoutSec=30
Restart=on-failure
StandardOutput=journal
StandardError=journal
SyslogIdentifier=patroni

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
```

## 6. Stop standalone PostgreSQL and start Patroni

```bash
# Stop standalone — Patroni takes over the existing data directory
systemctl stop postgresql-18
systemctl disable postgresql-18

# Start Patroni — it adopts /var/lib/postgresql/18/main as-is
systemctl enable --now patroni

systemctl status patroni

# Follow startup
journalctl -u patroni -f
```

## 7. Verify single-node cluster

```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml restart docpg-cls2 --force

# Expected: Role = Leader
curl -s http://172.18.0.21:8008 | python3 -m json.tool
curl -s http://172.18.0.21:8008/leader

sudo -u postgres psql -h 127.0.0.1 -p 5432 -d postgres -c "SELECT version();"
sudo -u postgres psql -h 127.0.0.1 -p 5432 -d postgres -c "\du"
```

---

# Part 5 — Add Replicas (docpg-cls2-pg2 and docpg-cls2-pg3)

> Perform all steps for each replica. Commands marked **[host]** run on ryzen9; all others run **inside the container**.

## docpg-cls2-pg2 (172.18.0.22)

### [host] Create volumes and container

```bash
docker volume create pg-cls2-data-pg2
docker volume create pg-cls2-logs-pg2

docker run -d \
  --name docpg-cls2-pg2 \
  --hostname docpg-cls2-pg2 \
  --network lab-network:ip=172.18.0.22 \
  --privileged \
  --cgroupns=host \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  --tmpfs /run \
  --tmpfs /run/lock \
  --volume pg-cls2-data-pg2:/var/lib/postgresql \
  --volume pg-cls2-logs-pg2:/var/log \
  --volume pg-backups:/var/lib/pgbackrest \
  --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --restart=unless-stopped \
  pg-cluster-node:latest

docker exec -it docpg-cls2-pg2 bash
```

### [inside docpg-cls2-pg2] /etc/hosts

```bash
cat >> /etc/hosts << 'EOF'
172.18.0.21     docpg-cls2-pg1
172.18.0.22     docpg-cls2-pg2
172.18.0.23     docpg-cls2-pg3
172.18.0.24     docpg-cls2-pg4
172.18.0.25     docpg-cls2-pg5
172.18.0.26     docpg-cls2-pg6
EOF
```

### [inside docpg-cls2-pg2] Install packages

```bash
apt-get update
install -d /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
  https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y \
  postgresql-18 postgresql-client-18 postgresql-contrib-18 \
  pgbackrest \
  python3 python3-pip python3-dev gcc curl wget jq acl less

pg_dropcluster --stop 18 main 2>/dev/null || true

mkdir -p /var/lib/postgresql/{18/main,log,scripts}
chown -R postgres:postgres /var/lib/postgresql
chmod -R 0750 /var/lib/postgresql

sudo -u postgres tee /var/lib/postgresql/.bash_profile > /dev/null << 'EOF2'
export PATH=/usr/lib/postgresql/18/bin:$PATH
export PGDATA=/var/lib/postgresql/18/main
export PGPORT=5432
export PGPASSFILE=/var/lib/postgresql/.pgpass
export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
EOF2

sudo -u postgres tee /var/lib/postgresql/.pgpass > /dev/null << 'EOF2'
*:*:*:postgres:YourSuperUserPassword
*:5432:*:replicator:YourReplicatorPassword
EOF2

chmod 0750 -R /var/lib/postgresql
chmod 0600 /var/lib/postgresql/.pgpass
```

### [inside docpg-cls2-pg2] Install etcd and Patroni

```bash
ETCD_VER=v3.6.12
curl -L \
  https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz \
  -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar -xzf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /usr/local/bin/ \
  --strip-components=1 \
  etcd-${ETCD_VER}-linux-amd64/etcd \
  etcd-${ETCD_VER}-linux-amd64/etcdctl

pip3 install "patroni[etcd3]" "psycopg[binary]" --break-system-packages
echo 'export PATH=/usr/local/bin:$PATH' > /etc/profile.d/local-bin.sh
export PATH=/usr/local/bin:$PATH
```

### [inside docpg-cls2-pg2] Configure etcd (joins pg1)

```bash
useradd --system --no-create-home --shell /sbin/nologin etcd 2>/dev/null || true
mkdir -p /etc/etcd /var/lib/etcd

tee /etc/etcd/etcd.conf > /dev/null << 'EOF'
ETCD_NAME="docpg-cls2-pg2"
ETCD_DATA_DIR="/var/lib/etcd"

ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://172.18.0.22:2379"

ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://172.18.0.22:2380"

ETCD_INITIAL_CLUSTER="docpg-cls2-pg1=http://172.18.0.21:2380,docpg-cls2-pg2=http://172.18.0.22:2380"
ETCD_INITIAL_CLUSTER_TOKEN="docpg-cls2-etcd"
ETCD_INITIAL_CLUSTER_STATE="existing"
EOF

chown -R etcd:etcd /etc/etcd/ /var/lib/etcd/
chmod 0644 /etc/etcd/etcd.conf

tee /etc/systemd/system/etcd.service > /dev/null << 'EOF'
[Unit]
Description=etcd distributed key-value store
After=network.target

[Service]
Type=notify
User=etcd
Group=etcd
EnvironmentFile=/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
```

> **Before starting etcd on pg2**, add the member on **pg1** first:

```bash
# Run this on docpg-cls2-pg1
etcdctl --endpoints=http://172.18.0.21:2379 \
  member add docpg-cls2-pg2 --peer-urls=http://172.18.0.22:2380
```

```bash
# Back on docpg-cls2-pg2
systemctl enable --now etcd
etcdctl --endpoints=http://172.18.0.21:2379,http://172.18.0.22:2379 member list
```

### [inside docpg-cls2-pg2] Configure pgbackrest

> The Docker named volume is already available at `/var/lib/pgbackrest` via the volume mount
> set in the container creation command. No mount needed inside the container.

```bash
mkdir -p /etc/pgbackrest
tee /etc/pgbackrest/pgbackrest.conf > /dev/null << 'EOF'
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
repo1-retention-diff=7
log-level-console=info
log-level-file=detail
log-path=/var/log/pgbackrest
process-max=4
compress-type=lz4
archive-async=y
spool-path=/var/spool/pgbackrest
archive-timeout=1800

[docpg-cls2]
pg1-path=/var/lib/postgresql/18/main
pg1-port=5432
pg1-user=postgres
EOF

chmod 755 /etc/pgbackrest/
chmod 644 /etc/pgbackrest/pgbackrest.conf
mkdir -p /var/log/pgbackrest /var/spool/pgbackrest
chown postgres:postgres /var/log/pgbackrest /var/spool/pgbackrest
```

### [inside docpg-cls2-pg2] Configure Patroni and join the cluster

```bash
mkdir -p /etc/patroni

tee /etc/patroni/patroni.yml > /dev/null << 'EOF'
scope: docpg-cls2
namespace: /db/
name: docpg-cls2-pg2

restapi:
  listen: 172.18.0.22:8008
  connect_address: 172.18.0.22:8008

etcd3:
  hosts: 172.18.0.21:2379,172.18.0.22:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        wal_keep_size: 1GB
        max_wal_senders: 10
        max_replication_slots: 10
        checkpoint_timeout: 30
        archive_mode: "on"
        archive_command: "pgbackrest --stanza=docpg-cls2 archive-push %p"
        restore_command: "pgbackrest --stanza=docpg-cls2 archive-get %f %p"

  slots:
    standby_cluster_slot:
      type: physical

  pg_hba:
    - "local   all             postgres                            peer"
    - "local   all             all                                 scram-sha-256"
    - "host    all             all             127.0.0.1/32        scram-sha-256"
    - "host    all             all             ::1/128             scram-sha-256"
    - "host    replication     replicator      127.0.0.1/32        scram-sha-256"
    - "host    replication     replicator      ::1/128             scram-sha-256"
    - "host    replication     replicator      172.18.0.0/24       scram-sha-256"
    - "host    all             all             172.18.0.0/24       scram-sha-256"
    - "host    all             all             192.168.100.0/24    scram-sha-256"

postgresql:
  listen: "0.0.0.0:5432"
  connect_address: "172.18.0.22:5432"
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/lib/postgresql/18/bin
  config_dir: /var/lib/postgresql/18/main
  pgpass: /var/lib/postgresql/.pgpass_patroni
  authentication:
    replication:
      username: replicator
      password: YourReplicatorPassword
    superuser:
      username: postgres
      password: YourSuperUserPassword
    rewind:
      username: postgres
      password: YourSuperUserPassword
  parameters:
    unix_socket_directories: "/var/run/postgresql,/tmp"
    log_directory: /var/log/postgresql
    logging_collector: "on"
    shared_buffers: 256MB

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

chown postgres:postgres /etc/patroni/ /etc/patroni/patroni.yml
chmod 0755 /etc/patroni/
chmod 0600 /etc/patroni/patroni.yml

tee /etc/systemd/system/patroni.service > /dev/null << 'EOF'
[Unit]
Description=Patroni — High Availability PostgreSQL Cluster Manager
After=syslog.target network.target etcd.service
Wants=etcd.service

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
ExecReload=/bin/kill -s HUP $MAINPID
KillMode=process
TimeoutSec=30
Restart=on-failure
StandardOutput=journal
StandardError=journal
SyslogIdentifier=patroni

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# Start Patroni — it will pg_basebackup from pg1 automatically
systemctl enable --now patroni

# Follow clone + startup progress
journalctl -u patroni -f
```

---

## docpg-cls2-pg3 (172.18.0.23)

Repeat the same steps as docpg-cls2-pg2 with these substitutions:

| Item | pg2 value | pg3 value |
|------|-----------|-----------|
| Container name | docpg-cls2-pg2 | docpg-cls2-pg3 |
| IP | 172.18.0.22 | 172.18.0.23 |
| Volume names | pg-cls2-data-pg2, pg-cls2-logs-pg2 | pg-cls2-data-pg3, pg-cls2-logs-pg3 |
| ETCD_NAME | docpg-cls2-pg2 | docpg-cls2-pg3 |
| ETCD_ADVERTISE_CLIENT_URLS | http://172.18.0.22:2379 | http://172.18.0.23:2379 |
| ETCD_INITIAL_ADVERTISE_PEER_URLS | http://172.18.0.22:2380 | http://172.18.0.23:2380 |
| ETCD_INITIAL_CLUSTER | pg1+pg2 | pg1+pg2+pg3 |
| /etc/hosts skips | pg2 entry | pg3 entry |

**Add pg3 member to etcd on pg1 before starting etcd on pg3:**

```bash
# On docpg-cls2-pg1
etcdctl --endpoints=http://172.18.0.21:2379,http://172.18.0.22:2379 \
  member add docpg-cls2-pg3 --peer-urls=http://172.18.0.23:2380
```

**etcd.conf ETCD_INITIAL_CLUSTER for pg3:**
```
ETCD_INITIAL_CLUSTER="docpg-cls2-pg1=http://172.18.0.21:2380,docpg-cls2-pg2=http://172.18.0.22:2380,docpg-cls2-pg3=http://172.18.0.23:2380"
ETCD_INITIAL_CLUSTER_STATE="existing"
```

---

# Part 6 — Verify the 3-Node Cluster

```bash
# From any node
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list

# Expected output:
# + Cluster: docpg-cls2 (xxxxxxxxxxxxxxx) ----+----+-----------+
# | Member           | Host            | Role    | State   | TL | Lag in MB |
# +------------------+-----------------+---------+---------+----+-----------+
# | docpg-cls2-pg1   | 172.18.0.21:5432| Leader  | running |  1 |           |
# | docpg-cls2-pg2   | 172.18.0.22:5432| Replica | running |  1 |         0 |
# | docpg-cls2-pg3   | 172.18.0.23:5432| Replica | running |  1 |         0 |
# +------------------+-----------------+---------+---------+----+-----------+

# Check etcd cluster health
etcdctl \
  --endpoints=http://172.18.0.21:2379,http://172.18.0.22:2379,http://172.18.0.23:2379 \
  endpoint health

# Check streaming replication from primary
sudo -u postgres psql -h 127.0.0.1 -p 5432 -d postgres \
  -c "SELECT client_addr, state, sent_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"

# Verify backups
docker exec docpg-cls2-pg1 pgbackrest --stanza=docpg-cls2 info
```

---

# Part 7 — Edit the 3-Node Cluster to have one synchronous replica

```bash
# Enable synchronous mode — one replica becomes Sync Standby
patronictl -c /etc/patroni/patroni.yml edit-config docpg-cls2 \
  --force --set synchronous_mode=true --set synchronous_node_count=1
```

---

# Part 8 — Update docpg-cls2-pg3 to be `nofailover` but allow to be sync standby

```bash
# Tag docpg-cls2-pg3 as nosync + nofailover
# Per-node tags are LOCAL settings — edit patroni.yml on pg3 directly, then reload.
#
# On docpg-cls2-pg3
vim /etc/patroni/patroni.yml

tags:
  nofailover: true
  nosync: false


systemctl restart patroni
```

---

# Part 9 — Set up docpg-cls2-pg4 as a Standby Cluster

> `docpg-cls2-pg4` runs in **Patroni standby cluster mode**. It streams WAL from the
> primary cluster leader (`docpg-cls2-pg1`, 172.18.0.21) and remains read-only until
> explicitly promoted. It has its **own single-node etcd** — it does **not** join the
> pg1/pg2/pg3 etcd cluster.
>
> Commands marked **[host]** run on **ryzen9**; all others run **inside the container**.

## Key Differences from pg2/pg3

| Feature                  | pg2 / pg3 (primary-cluster replicas) | pg4 (standby cluster)              |
|--------------------------|--------------------------------------|------------------------------------|
| etcd                     | Shared 3-node cluster (pg1+pg2+pg3)  | Own single-node etcd on pg4        |
| Patroni scope            | docpg-cls2                           | docpg-cls2 (same — enables failback)|
| Streams from             | Primary cluster leader               | Primary cluster leader (172.18.0.21)|
| `standby_cluster` block  | Not set                              | Set — host: 172.18.0.21, port: 5432|
| Write queries            | Via leader only                      | Read-only until promoted           |

---

## [host] Create volumes and container

```bash
docker volume create pg-cls2-data-pg4
docker volume create pg-cls2-logs-pg4

docker run -d \
  --name docpg-cls2-pg4 \
  --hostname docpg-cls2-pg4 \
  --network lab-network:ip=172.18.0.24 \
  --privileged \
  --cgroupns=host \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  --tmpfs /run \
  --tmpfs /run/lock \
  --volume pg-cls2-data-pg4:/var/lib/postgresql \
  --volume pg-cls2-logs-pg4:/var/log \
  --volume pg-backups:/var/lib/pgbackrest \
  --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --restart=unless-stopped \
  pg-cluster-node:latest

# Verify container is up
docker ps --filter name=docpg-cls2-pg4

docker exec -it docpg-cls2-pg4 bash
```

---

## [inside docpg-cls2-pg4] /etc/hosts

```bash
cat >> /etc/hosts << 'EOF'
172.18.0.21     docpg-cls2-pg1
172.18.0.22     docpg-cls2-pg2
172.18.0.23     docpg-cls2-pg3
172.18.0.24     docpg-cls2-pg4
172.18.0.25     docpg-cls2-pg5
172.18.0.26     docpg-cls2-pg6
EOF
```

---

## [inside docpg-cls2-pg4] Install packages

```bash
apt-get update
install -d /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
  https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list

apt-get update

apt-get install -y \
  postgresql-18 postgresql-client-18 postgresql-contrib-18 \
  pgbackrest \
  python3 python3-pip python3-dev gcc curl wget jq acl less vim

pg_dropcluster --stop 18 main 2>/dev/null || true

mkdir -p /var/lib/postgresql/{18/main,log,scripts}
chown -R postgres:postgres /var/lib/postgresql
chmod -R 0750 /var/lib/postgresql

sudo -u postgres tee /var/lib/postgresql/.bash_profile > /dev/null << 'EOF2'
export PATH=/usr/lib/postgresql/18/bin:$PATH
export PGDATA=/var/lib/postgresql/18/main
export PGPORT=5432
export PGPASSFILE=/var/lib/postgresql/.pgpass
export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
EOF2

sudo -u postgres tee /var/lib/postgresql/.pgpass > /dev/null << 'EOF2'
*:*:*:postgres:YourSuperUserPassword
*:5432:*:replicator:YourReplicatorPassword
EOF2

chmod 0750 -R /var/lib/postgresql
chmod 0600 /var/lib/postgresql/.pgpass
```

---

## [inside docpg-cls2-pg4] Install etcd and Patroni

> pg4 runs its **own standalone etcd** — do **not** run `etcdctl member add` on pg1.

```bash
ETCD_VER=v3.6.12

curl -L \
  https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz \
  -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz

tar -xzf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /usr/local/bin/ \
  --strip-components=1 \
  etcd-${ETCD_VER}-linux-amd64/etcd \
  etcd-${ETCD_VER}-linux-amd64/etcdctl

rm /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
etcd --version

pip3 install patroni[etcd3] 'psycopg[binary]' --break-system-packages

# Create etcd user and data directory
useradd -r -s /sbin/nologin etcd 2>/dev/null || true
mkdir -p /var/lib/etcd
chown etcd:etcd /var/lib/etcd
chmod 0700 /var/lib/etcd
```

### Configure etcd (single-node)

```bash
mkdir -p /etc/etcd

tee /etc/etcd/etcd.conf > /dev/null << 'EOF'
ETCD_NAME="docpg-cls2-pg4"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://172.18.0.24:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://172.18.0.24:2380"
ETCD_INITIAL_CLUSTER="docpg-cls2-pg4=http://172.18.0.24:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="docpg-cls2-etcd"
EOF

tee /etc/systemd/system/etcd.service > /dev/null << 'EOF'
[Unit]
Description=etcd distributed key-value store
After=network.target

[Service]
Type=notify
User=etcd
Group=etcd
EnvironmentFile=/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now etcd
systemctl status etcd

# Verify single-node etcd is healthy
etcdctl --endpoints=http://172.18.0.24:2379 endpoint health
```

---

## [inside docpg-cls2-pg4] Configure pgbackrest

> pg4 uses the same shared backup repository as pg1/pg2/pg3 (read-only for restore).
> No stanza-create is needed — the stanza already exists on the shared mount.

```bash
mkdir -p /etc/pgbackrest

tee /etc/pgbackrest/pgbackrest.conf > /dev/null << 'EOF'
[global]
# Docker named volume mounted into the container at /var/lib/pgbackrest
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
repo1-retention-diff=7
log-level-console=info
log-level-file=detail
log-path=/var/log/pgbackrest

process-max=4
compress-type=lz4
compress-level=3

archive-async=y
spool-path=/var/spool/pgbackrest
archive-queue-max=268435456
archive-timeout=1800

[docpg-cls2]
pg1-path=/var/lib/postgresql/18/main
pg1-port=5432
pg1-user=postgres
EOF

chmod 755 /etc/pgbackrest/
chmod 644 /etc/pgbackrest/pgbackrest.conf
mkdir -p /var/log/pgbackrest /var/spool/pgbackrest
chown postgres:postgres /var/log/pgbackrest /var/spool/pgbackrest
```

---

## [inside docpg-cls2-pg4] Configure Patroni (standby cluster mode)

```bash
mkdir -p /etc/patroni

tee /etc/patroni/patroni.yml > /dev/null << 'EOF'
scope: docpg-cls2
namespace: /db/
name: docpg-cls2-pg4

restapi:
  listen: 172.18.0.24:8008
  connect_address: 172.18.0.24:8008

etcd3:
  hosts: 172.18.0.24:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    standby_cluster:
      host: 172.18.0.21
      port: 5432
      primary_slot_name: "standby_cluster_slot"
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        wal_keep_size: 1GB
        max_wal_senders: 10
        max_replication_slots: 10
        checkpoint_timeout: 30
        archive_mode: "on"
        archive_command: "pgbackrest --stanza=docpg-cls2 archive-push %p"
        restore_command: "pgbackrest --stanza=docpg-cls2 archive-get %f %p"

  pg_hba:
    - "local   all             postgres                            peer"
    - "local   all             all                                 scram-sha-256"
    - "host    all             all             127.0.0.1/32        scram-sha-256"
    - "host    all             all             ::1/128             scram-sha-256"
    - "host    replication     replicator      127.0.0.1/32        scram-sha-256"
    - "host    replication     replicator      ::1/128             scram-sha-256"
    - "host    replication     replicator      172.18.0.0/24       scram-sha-256"
    - "host    all             all             172.18.0.0/24       scram-sha-256"
    - "host    all             all             192.168.100.0/24    scram-sha-256"

postgresql:
  listen: "0.0.0.0:5432"
  connect_address: "172.18.0.24:5432"
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/lib/postgresql/18/bin
  config_dir: /var/lib/postgresql/18/main
  pgpass: /var/lib/postgresql/.pgpass_patroni
  authentication:
    replication:
      username: replicator
      password: YourReplicatorPassword
    superuser:
      username: postgres
      password: YourSuperUserPassword
    rewind:
      username: postgres
      password: YourSuperUserPassword
  parameters:
    unix_socket_directories: "/var/run/postgresql,/tmp"
    log_directory: /var/log/postgresql
    log_filename: "postgresql-%Y-%m-%d_%H%M%S.log"
    logging_collector: "on"
    shared_buffers: 256MB

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

chown postgres:postgres /etc/patroni/ /etc/patroni/patroni.yml
chmod 0755 /etc/patroni/
chmod 0600 /etc/patroni/patroni.yml

tee /etc/systemd/system/patroni.service > /dev/null << 'EOF'
[Unit]
Description=Patroni — High Availability PostgreSQL Cluster Manager
After=syslog.target network.target etcd.service
Wants=etcd.service

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
ExecReload=/bin/kill -s HUP $MAINPID
KillMode=process
TimeoutSec=30
Restart=on-failure
StandardOutput=journal
StandardError=journal
SyslogIdentifier=patroni

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# Start Patroni — it will pg_basebackup from docpg-cls2-pg1 automatically
systemctl enable --now patroni

# Follow clone + startup progress
journalctl -u patroni -f
```

---

## Verify the Standby Cluster

```bash
# From docpg-cls2-pg4 — check Patroni sees it as Standby Leader
patronictl -c /etc/patroni/patroni.yml list
# Expected:
# + Cluster: docpg-cls2 (standby) ---+----------------+----+-----+
# | Member         | Host        | Role           | State     | TL | Lag |
# +----------------+-------------+----------------+-----------+----+-----+
# | docpg-cls2-pg4 | 172.18.0.24 | Standby Leader | streaming |  N |   0 |

# From docpg-cls2-pg1 — confirm pg4 appears as a streaming replica
sudo -u postgres psql -h 127.0.0.1 -p 5432 -d postgres \
  -c "SELECT client_addr, state, sync_state, sent_lsn, replay_lsn,
             ROUND((sent_lsn - replay_lsn)/1048576.0,2) AS lag_mb
      FROM pg_stat_replication
      WHERE client_addr = '172.18.0.24';"

# Verify pg4 is in recovery (standby mode)
sudo -u postgres psql -h 172.18.0.24 -p 5432 -d postgres \
  -c "SELECT pg_is_in_recovery();"
# Expected: t

# Check streaming lag on pg4
sudo -u postgres psql -h 172.18.0.24 -p 5432 -d postgres \
  -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"

# Verify pg4's local etcd is healthy
etcdctl --endpoints=http://172.18.0.24:2379 endpoint health

# Monitor pg4 Patroni log
journalctl -u patroni -f
```

---

## Promote the Standby Cluster (DR only)

Use this only when the entire primary cluster (pg1/pg2/pg3) is down and pg4 must accept writes.

```bash
# On docpg-cls2-pg4 — promote the standby to become an autonomous primary
patronictl -c /etc/patroni/patroni.yml edit-config docpg-cls2 \
  --force --set standby_cluster=null

# Patroni will restart PostgreSQL in read-write mode and elect pg4 as Leader
patronictl -c /etc/patroni/patroni.yml list
```

---

# Useful Commands

> Run as postgres user: `sudo su - postgres` or use full path `/usr/local/bin/patronictl`

```bash
# List cluster members
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list

# Show failover history
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml history

# Planned switchover
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml switchover docpg-cls2

# Reinitialize a replica
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml reinit docpg-cls2 docpg-cls2-pg2

# Pause / resume automatic failover
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml pause  docpg-cls2
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml resume docpg-cls2

# Edit DCS-stored cluster config
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml edit-config docpg-cls2

# pgbackrest — full backup (run on leader)
docker exec docpg-cls2-pg1 sudo -u postgres \
  pgbackrest --stanza=docpg-cls2 --type=full backup

# pgbackrest — show backup info
docker exec docpg-cls2-pg1 pgbackrest --stanza=docpg-cls2 info

# Connect to cluster via host port
psql -h 127.0.0.1 -p 5441 -U postgres -d postgres   # pg1
psql -h 127.0.0.1 -p 5442 -U postgres -d postgres   # pg2
psql -h 127.0.0.1 -p 5443 -U postgres -d postgres   # pg3
```

