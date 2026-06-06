# [Convert a Standalone to a Patroni Cluster on RHEL](https://patroni.readthedocs.io/en/latest/existing_data.html)

Host - sqlred (192.168.100.55)
postgres user home directory - /var/lib/postgresql/
password to be managed by ~/.pgpass files in postgres user home directory
pgbackrest backup path - saanvi@ryzen9:/stale-storage/share-stalestorage/pgbackrest_backups

# Tools to use
- postgresql 18
- patroni latest
- pgbackrest latest
- etcd latest
- postgres_exporter latest

# Prerequisites

- RHEL 9 (or compatible) installed on all nodes
- Root or `sudo` access on all nodes
- Nodes can reach each other on the following ports:
  - `5432` – PostgreSQL
  - `8008` – Patroni REST API
  - `2379` / `2380` – etcd client / peer
  - `9187` – postgres_exporter (Prometheus scrape)
- Internet access (or a configured local mirror) for package installation

---

# For fixing internet issue
```
saanvi@sqlred:~$ ip a
2: enp1s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    inet 192.168.100.55/24 brd 192.168.100.255 scope global noprefixroute enp1s0
3: enp7s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    inet 192.168.122.237/24 brd 192.168.122.255 scope global dynamic noprefixroute enp7s0

Target Config
----------------
Nic enp1s0 should only have a static route for 192.168.0.0/16 via 192.168.100.1
Nic enp7s0 should have the default route (already given by DHCP, just need to stop enp1s0 from overriding it)

# 1. See the current connection profile names
nmcli connection show

# 2. Fix enp1s0:
#    - never install a default route from this interface
#    - add a static route covering all of 192.168.0.0/16 via the lab gateway
sudo nmcli connection modify enp1s0 \
  ipv4.never-default yes \
  ipv4.routes "192.168.0.0/16 192.168.100.1"

# 3. Fix enp7s0:
#    - ensure it IS allowed to provide the default route (DHCP gives 192.168.122.1)
sudo nmcli connection modify enp7s0 \
  ipv4.never-default no

# 4. Apply changes (bring connections down and back up)
sudo nmcli connection up enp1s0
sudo nmcli connection up enp7s0

# 5. Verify the routing table
ip route show


Expected Output Should Look Like
--------------------------------
default via 192.168.122.1 dev enp7s0         # internet via NAT
192.168.0.0/16 via 192.168.100.1 dev enp1s0  # whole 192.168.x.x via lab
192.168.100.0/24 dev enp1s0 proto kernel      # directly connected (auto)
192.168.122.0/24 dev enp7s0 proto kernel      # directly connected (auto)

```

# Set Up postgres User Home Directory

> On RHEL, the `postgres` user's default home is `/var/lib/pgsql`. The steps below create the user/group if they do not already exist, then relocate the home to `/var/lib/postgresql/` as required by this guide. Run these commands **on every node** (primary and all replicas).

```bash
# Create the postgres system group (no-op if it already exists)
sudo groupadd --system postgres 2>/dev/null || true

# Create the postgres system user with /var/lib/postgresql as its home directory.
# If the user already exists (e.g. created by a prior PostgreSQL install),
# the command is skipped gracefully and usermod below will update the home path.
sudo useradd \
  --system \
  --gid postgres \
  --home-dir /var/lib/postgresql \
  --create-home \
  --shell /bin/bash \
  --comment "PostgreSQL Server" \
  postgres 2>/dev/null || true

# Create the target home directory (idempotent; already created by useradd above)
sudo mkdir -p /var/lib/postgresql

# Relocate the postgres user home and set the login shell
# (handles the case where the user pre-existed with a different home)
sudo usermod -d /var/lib/postgresql -s /bin/bash postgres

# Grant ownership to the postgres user
sudo chown -R postgres:postgres /var/lib/postgresql

# Create sub-directories used throughout this guide
sudo -u postgres mkdir -p /var/lib/postgresql/{18/main,log,scripts}

# Write the postgres user shell profile
sudo -u postgres tee /var/lib/postgresql/.bash_profile > /dev/null << 'EOF'
# PostgreSQL 18 environment
export PATH=/usr/pgsql-18/bin:$PATH
export PGDATA=/var/lib/postgresql/18/main
export PGPORT=5432
export PGPASSFILE=/var/lib/postgresql/.pgpass
export PATRONICTL_CONFIG_FILE=/var/lib/postgresql/patroni.yml
EOF

# Apply the profile in the current session
sudo -u postgres bash -c "source /var/lib/postgresql/.bash_profile"
```

---

# Install PostgreSQL 18 on RHEL (Manual)

## 1. Install PostgreSQL 18 from the PGDG Repository

```bash
# Detect the RHEL major version automatically (works on RHEL 9, 10, …)
EL_VER=$(rpm -E %{rhel})

# Add the PostgreSQL Global Development Group (PGDG) repository
sudo dnf install -y \
  https://download.postgresql.org/pub/repos/yum/reporpms/EL-${EL_VER}-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Disable the built-in postgresql module to avoid conflicts
sudo dnf -qy module disable postgresql

# Enable CodeReady Builder (CRB) – required by EPEL as a dependency source
sudo subscription-manager repos --enable codeready-builder-for-rhel-${EL_VER}-$(arch)-rpms

# Install EPEL for the detected RHEL major version
# (on RHEL 10 'epel-release' is not a DNF package; install directly from Fedora)
sudo dnf install -y \
  https://dl.fedoraproject.org/pub/epel/epel-release-latest-${EL_VER}.noarch.rpm

# Install libssh2 – required by pgbackrest >= 2.55 for remote SFTP repository support
sudo dnf install -y libssh2

# Install PostgreSQL 18 server and common extensions
sudo dnf install -y postgresql18-server postgresql18 postgresql18-contrib postgresql18-libs

# Verify the installation
/usr/pgsql-18/bin/postgres --version
```

## 2. Initialize the Database Cluster

```bash
# Initialize the data directory inside the postgres user home
sudo -u postgres /usr/pgsql-18/bin/initdb \
  --encoding=UTF8 \
  --data-checksums \
  --pgdata=/var/lib/postgresql/18/main \
  --auth-local=peer \
  --auth-host=scram-sha-256

# Confirm the data directory was created
sudo -u postgres ls -la /var/lib/postgresql/18/main/
```

## 3. Configure postgresql.conf

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

# Archive (managed by pgbackrest via Patroni DCS config)
archive_mode = on
#archive_command = 'pgbackrest --config=/etc/pgbackrest/pgbackrest.conf --stanza=sqlred archive-push %p'
#restore_command = 'pgbackrest --config=/etc/pgbackrest/pgbackrest.conf --stanza=sqlred archive-get %f %p'
archive_command = 'pgbackrest --stanza=sqlred archive-push %p'
restore_command = 'pgbackrest --stanza=sqlred archive-get %f %p'

# Logging – log files stored inside postgres home
logging_collector = on
log_directory = '/var/lib/postgresql/log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_connections = on
log_disconnections = on
log_checkpoints = on
log_lock_waits = on
log_min_duration_statement = 5000

# Performance (tune to actual server memory)
shared_buffers = 256MB
effective_cache_size = 768MB
checkpoint_timeout = 30
EOF
```

## 4. Configure pg_hba.conf

```bash
sudo -u postgres tee /var/lib/postgresql/18/main/pg_hba.conf > /dev/null << 'EOF'
# TYPE  DATABASE        USER            ADDRESS                  METHOD
# Local OS-level authentication
local   all             postgres                                 peer
local   all             all                                      scram-sha-256

# IPv4 loopback
host    all             all              127.0.0.1/32            scram-sha-256

# Streaming replication
host    replication     replicator       127.0.0.1/32            scram-sha-256
host    replication     replicator       192.168.100.0/24        scram-sha-256

# pg_rewind
host    all             replicator      127.0.0.1/32            scram-sha-256
host    all             replicator      192.168.100.0/24        scram-sha-256

# Application connections
host    all             all              192.168.100.0/24        scram-sha-256
EOF
```

## 5. Create the .pgpass File in postgres Home Directory

```bash
# Passwords for all PostgreSQL users – stored in postgres user home
sudo -u postgres tee /var/lib/postgresql/.pgpass > /dev/null << 'EOF'
# hostname:port:database:username:password
*:*:*:*:YourStrongSuperUserPassword
*:5432:*:replicator:YourReplicatorPassword
EOF

# PostgreSQL refuses to read .pgpass if it is world- or group-readable
sudo chmod 0600 /var/lib/postgresql/.pgpass
```

## 6. Create a systemd Override for the PostgreSQL 18 Service

```bash
sudo mkdir -p /etc/systemd/system/postgresql-18.service.d/

sudo tee /etc/systemd/system/postgresql-18.service.d/override.conf > /dev/null << 'EOF'
[Service]
Environment=PGDATA=/var/lib/postgresql/18/main
User=postgres
Group=postgres
EOF

sudo systemctl daemon-reload
sudo systemctl enable postgresql-18
sudo systemctl start postgresql-18
sudo systemctl status postgresql-18
```

## 7. Install pgbackrest on sqlred

```bash
# pgbackrest is available in the PGDG repository added above
sudo dnf install -y pgbackrest

pgbackrest version
```

## 8. Configure pgbackrest on sqlred

The pgbackrest configuration on `sqlred` is stored at `/etc/pgbackrest/pgbackrest.conf` — the system-wide default location that pgbackrest reads without requiring any environment variable. This is preferred over the XDG user config (`~/.config/pgbackrest/pgbackrest.conf`) because the PostgreSQL archiver process does **not** source `.bash_profile`, so environment variables like `PGBACKREST_CONFIG` are never available to it.

Choose **one** of the two methods below depending on whether the backup repository is accessed over SSH or via a locally mounted shared directory.

| | Method 01 — SSH (Remote Repository) | Method 02 — Shared Directory (No SSH) |
|---|---|---|
| **Transport** | pgbackrest SSH protocol | CIFS/SMB network mount |
| **pgbackrest on ryzen9** | Required | Not required |
| **SSH key exchange** | Required (both directions) | Not required |
| **When to use** | General case; ryzen9 is a dedicated backup server | ryzen9 exports a Samba share that sqlred can mount directly |

---

### Method 01: Remote Repository via SSH

pgbackrest uses its own SSH channel to stream WAL and backup data to a remote repository host. Both hosts must have pgbackrest installed and must trust each other's `postgres` SSH keys.

> [!CAUTION]
> **pgbackrest version must be identical on both hosts.**
> When using SSH-based remote repository, pgbackrest on `sqlred` (RHEL) and pgbackrest on `ryzen9` (Ubuntu) must be the **exact same version** — including patch level (e.g. `2.58.0`). A version mismatch causes the remote process to fail with a protocol error immediately at connection time.
>
> Always verify before running any pgbackrest command:
> ```bash
> # On sqlred
> pgbackrest version
>
> # On ryzen9
> pgbackrest version
> ```
> If the versions differ, upgrade the older host to match before proceeding.
> Method 02 (shared directory) has no such constraint because pgbackrest runs only on sqlred.

#### Add ryzen9 to /etc/hosts on sqlred
```bash
echo "192.168.100.1 ryzen9" | sudo tee -a /etc/hosts
```

#### pgbackrest config on sqlred
```bash
sudo mkdir -p /etc/pgbackrest

sudo tee /etc/pgbackrest/pgbackrest.conf > /dev/null << 'EOF'
[global]
repo1-host=ryzen9
repo1-host-user=postgres
repo1-path=/stale-storage/share-stalestorage/pgbackrest_backups
repo1-retention-full=2
repo1-retention-diff=7
log-level-console=info
log-level-file=detail
log-path=/var/lib/postgresql/log

[sqlred]
pg1-path=/var/lib/postgresql/18/main
pg1-port=5432
pg1-user=postgres
EOF

sudo chmod 755 /etc/pgbackrest/
sudo chmod 644 /etc/pgbackrest/pgbackrest.conf
```

#### Set Up SSH Key Trust Between sqlred and ryzen9 postgres Users

pgbackrest requires passwordless SSH in **both directions** between the `postgres` user on each host.

**On sqlred:**
```bash
# Create .ssh directory for the postgres user
sudo -u postgres mkdir -p /var/lib/postgresql/.ssh
sudo -u postgres chmod 0700 /var/lib/postgresql/.ssh

# Generate an ed25519 key pair (no passphrase)
sudo -u postgres ssh-keygen -t ed25519 -N "" \
  -f /var/lib/postgresql/.ssh/id_ed25519 \
  -C "postgres@sqlred"

# Copy sqlred's postgres public key to ryzen9's authorized_keys
sudo -u postgres ssh-copy-id -i /var/lib/postgresql/.ssh/id_ed25519.pub \
  postgres@ryzen9

# Verify connectivity: sqlred → ryzen9
sudo -u postgres ssh postgres@ryzen9 "hostname && id"
```

**On ryzen9:**
```bash
# Create .ssh directory for the postgres user on ryzen9
sudo mkdir -p /var/lib/postgresql/.ssh
sudo chmod 0700 /var/lib/postgresql/.ssh
sudo chown postgres:postgres /var/lib/postgresql/.ssh

# Generate an ed25519 key pair for ryzen9's postgres user
sudo -u postgres ssh-keygen -t ed25519 -N "" \
  -f /var/lib/postgresql/.ssh/id_ed25519 \
  -C "postgres@ryzen9"

# Copy ryzen9's postgres public key to sqlred's authorized_keys
sudo -u postgres ssh-copy-id -i /var/lib/postgresql/.ssh/id_ed25519.pub \
  postgres@192.168.100.55

# Verify connectivity: ryzen9 → sqlred
sudo -u postgres ssh postgres@192.168.100.55 "hostname && id"
```

#### Install and Configure pgbackrest on ryzen9 (Repository Host)

> Run the following on **ryzen9**.

```bash
# Install pgbackrest (ryzen9 is Ubuntu)
sudo apt-get install -y pgbackrest

# ryzen9 only needs repo1-path so its local pgbackrest process can write backup
# files. pg1-host / pg1-path are NOT set here — sqlred handles the PG connection.
sudo mkdir -p /etc/pgbackrest

sudo tee /etc/pgbackrest/pgbackrest.conf > /dev/null << 'EOF'
[global]
repo1-path=/stale-storage/share-stalestorage/pgbackrest_backups

[sqlred]
EOF

sudo chmod 755 /etc/pgbackrest/
sudo chmod 644 /etc/pgbackrest/pgbackrest.conf

# Create the backup repository directory
sudo mkdir -p /stale-storage/share-stalestorage/pgbackrest_backups
sudo chown postgres:postgres /stale-storage/share-stalestorage/pgbackrest_backups
sudo chmod 0755 /stale-storage/share-stalestorage/pgbackrest_backups

# Named group ACE — survives pgbackrest's explicit chmod calls on every file it writes.
# (The traditional "other::" ACL entry would be overwritten by pgbackrest's chmod;
#  named group ACEs are never touched by chmod.)
sudo groupadd pgbackup-readers
sudo usermod -aG pgbackup-readers saanvi   # repeat for other users as needed

sudo setfacl -R    -m g:pgbackup-readers:rx /stale-storage/share-stalestorage/pgbackrest_backups
sudo setfacl -R -d -m g:pgbackup-readers:rx /stale-storage/share-stalestorage/pgbackrest_backups

# pgbackrest log directory on ryzen9
sudo mkdir -p /var/log/pgbackrest
sudo chown postgres:postgres /var/log/pgbackrest
```

---

### Method 02: Shared Directory (No SSH Required)

When the repository path (`/stale-storage/share-stalestorage/`) is a Samba share exported by ryzen9, sqlred can mount it directly via CIFS. pgbackrest then treats it as a plain local path (`repo1-type=posix`, the default) — no SSH tunnel, no pgbackrest process on ryzen9 required.

#### Mount the Samba share on sqlred

> Run the following on **sqlred**.

```bash
# Install CIFS client utilities
# RHEL / CentOS / Rocky
sudo dnf install -y cifs-utils

# Ubuntu / Debian
# sudo apt install -y cifs-utils

# Create the local mount point
sudo mkdir -p /mnt/pgbackrest-repo

# Test the mount (the share has guest access enabled)
# mfsymlinks — required by pgbackrest: it creates a 'latest' symlink after every
# backup. Standard CIFS mounts do not support symlinks; mfsymlinks enables symlink
# emulation using a Microsoft filesystem extension so the operation succeeds.
sudo mount -t cifs //ryzen9/share-stalestorage /mnt/pgbackrest-repo \
  -o guest,uid=postgres,gid=postgres,dir_mode=0755,file_mode=0644,nobrl,mfsymlinks

# Confirm the postgres user can write to the mount
sudo -u postgres touch /mnt/pgbackrest-repo/test && \
  echo "Write OK" && \
  sudo rm /mnt/pgbackrest-repo/test

# Make the mount permanent (survives reboots)
# _netdev tells systemd to mount only after the network is up
echo '//ryzen9/share-stalestorage  /mnt/pgbackrest-repo  cifs  guest,uid=postgres,gid=postgres,dir_mode=0755,file_mode=0644,nobrl,mfsymlinks,_netdev  0  0' \
  | sudo tee -a /etc/fstab
```

#### pgbackrest config on sqlred
```bash
sudo mkdir -p /etc/pgbackrest

sudo tee /etc/pgbackrest/pgbackrest.conf > /dev/null << 'EOF'
[global]
# Direct path on the CIFS mount — no SSH or remote pgbackrest process needed
repo1-path=/mnt/pgbackrest-repo/pgbackrest_backups
repo1-retention-full=2
repo1-retention-diff=7
log-level-console=info
log-level-file=detail
log-path=/var/lib/postgresql/log

[sqlred]
pg1-path=/var/lib/postgresql/18/main
pg1-port=5432
pg1-user=postgres
EOF

sudo chmod 755 /etc/pgbackrest/
sudo chmod 644 /etc/pgbackrest/pgbackrest.conf

# Create the backup repository directory on the mount
sudo -u postgres mkdir -p /mnt/pgbackrest-repo/pgbackrest_backups
```

---

## 9. Create the pgbackrest Stanza and Take the Initial Backup

> Run on **sqlred** — PostgreSQL must be running as a standalone service at this point.
> These steps are identical for both Method 01 and Method 02.

> **Why `sudo -i -u postgres`**: The config is at `/etc/pgbackrest/pgbackrest.conf` — a system default that pgbackrest finds without any environment variable. `sudo -i -u postgres` is still preferred here because it sources `.bash_profile`, making `PATH`, `PGDATA`, and other env vars available for the `psql` commands that follow.

```bash
# Switch to a full postgres login shell (sources .bash_profile)
sudo -i -u postgres

# Create the stanza (initialises the repository directory structure)
pgbackrest --stanza=sqlred stanza-create

# Run a configuration check end-to-end
pgbackrest --stanza=sqlred check

# Take the first full backup
pgbackrest --stanza=sqlred --type=full backup

# Confirm backup is visible
pgbackrest --stanza=sqlred info

# Exit the postgres shell when done
exit
```


> **Important**: Once Patroni is running it manages the PostgreSQL process. **Do not** start `postgresql-18.service` directly — keep it **disabled**.

```bash
sudo systemctl disable postgresql-18
```

---
---

# Convert Standalone PostgreSQL to Patroni Cluster with Single Node

## 1. Install etcd

### Option A – Install via EPEL

```bash
sudo dnf install -y epel-release
sudo dnf install -y etcd

etcd --version
```

### Option B – Install from Official Binary

```bash
ETCD_VER=v3.5.21

curl -L \
  https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz \
  -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz

sudo tar -xzf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /usr/local/bin/ \
  --strip-components=1 \
  etcd-${ETCD_VER}-linux-amd64/etcd \
  etcd-${ETCD_VER}-linux-amd64/etcdctl

etcd --version
etcdctl version
```

## 2. Install Patroni

```bash
# Python build dependencies
sudo dnf install -y python3 python3-pip python3-devel gcc

# Install Patroni with etcd3 support
sudo pip3 install patroni[etcd3]

patroni --version
```

## 3. Install postgres_exporter

> **Note**: pgbackrest was already installed and configured in **Steps 7–9** of the *Install PostgreSQL 18 on RHEL* section above (either SSH or shared-directory method). No further pgbackrest installation or configuration is needed here.

```bash
# Fetch the latest release tag from GitHub
PG_EXPORTER_VER=$(curl -s https://api.github.com/repos/prometheus-community/postgres_exporter/releases/latest \
  | grep '"tag_name"' | cut -d '"' -f 4)

curl -L \
  "https://github.com/prometheus-community/postgres_exporter/releases/download/${PG_EXPORTER_VER}/postgres_exporter-${PG_EXPORTER_VER#v}.linux-amd64.tar.gz" \
  -o /tmp/postgres_exporter.tar.gz

sudo tar -xzf /tmp/postgres_exporter.tar.gz -C /usr/local/bin/ \
  --strip-components=1

postgres_exporter --version
```

## 5. Configure etcd (Single Node)

```bash
sudo tee /etc/etcd/etcd.conf > /dev/null << 'EOF'
ETCD_NAME="sqlred"
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"

# Client communication
ETCD_LISTEN_CLIENT_URLS="http://192.168.100.55:2379,http://127.0.0.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.100.55:2379"

# Peer communication
ETCD_LISTEN_PEER_URLS="http://192.168.100.55:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.100.55:2380"

# Bootstrap cluster
ETCD_INITIAL_CLUSTER="sqlred=http://192.168.100.55:2380"
ETCD_INITIAL_CLUSTER_TOKEN="patroni-etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF

sudo systemctl enable --now etcd

# Confirm etcd is healthy
etcdctl --endpoints=http://192.168.100.55:2379 endpoint health
```

## 6. Configure Patroni

### Create patroni.yml in the postgres User Home Directory

```bash
sudo -u postgres tee /var/lib/postgresql/patroni.yml > /dev/null << 'EOF'
scope: postgres-cluster
namespace: /db/
name: sqlred

restapi:
  listen: 192.168.100.55:8008
  connect_address: 192.168.100.55:8008

etcd3:
  hosts: 192.168.100.55:2379

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
        archive_command: "pgbackrest --stanza=sqlred archive-push %p"
        restore_command: "pgbackrest --stanza=sqlred archive-get %f %p"

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - "local   all             postgres                            peer"
    - "local   all             all                                 scram-sha-256"
    - "host    all             all             127.0.0.1/32        scram-sha-256"
    - "host    replication     replicator      127.0.0.1/32        scram-sha-256"
    - "host    replication     replicator      192.168.100.0/24    scram-sha-256"
    - "host    all             all             192.168.100.0/24    scram-sha-256"

  users:
    admin:
      password: YourAdminPassword
      options:
        - createrole
        - createdb

postgresql:
  listen: "192.168.100.55:5432,127.0.0.1:5432"
  connect_address: "192.168.100.55:5432"
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/pgsql-18/bin
  config_dir: /var/lib/postgresql/18/main
  pgpass: /var/lib/postgresql/.pgpass
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
    log_directory: /var/lib/postgresql/log
    log_filename: "postgresql-%Y-%m-%d_%H%M%S.log"
    logging_collector: "on"
    shared_buffers: 256MB

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

# Restrict permissions
sudo chmod 0600 /var/lib/postgresql/patroni.yml
```

### Create Patroni systemd Service

```bash
sudo tee /etc/systemd/system/patroni.service > /dev/null << 'EOF'
[Unit]
Description=Patroni – High Availability PostgreSQL Cluster Manager
After=syslog.target network.target etcd.service
Wants=etcd.service

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /var/lib/postgresql/patroni.yml
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

sudo systemctl daemon-reload
```

## 7. pgbackrest

> pgbackrest is already installed, configured, and tested in **Steps 7–9** of the *Install PostgreSQL 18 on RHEL* section.
> The configuration at `/etc/pgbackrest/pgbackrest.conf` points to the backup repository (either via SSH to ryzen9 for Method 01, or via the CIFS mount at `/mnt/pgbackrest-repo` for Method 02).
> The `archive_command` and `restore_command` hard-code `--config=/etc/pgbackrest/pgbackrest.conf`, so pgbackrest finds its settings even when called from the PostgreSQL archiver process (which does not source `.bash_profile`).

## 8. Configure postgres_exporter

```bash
# Environment file in postgres user home
sudo -u postgres tee /var/lib/postgresql/postgres_exporter.env > /dev/null << 'EOF'
# pgpass provides the password; no plaintext credential in this file
DATA_SOURCE_NAME=postgresql://postgres@localhost:5432/postgres?sslmode=disable&passfile=/var/lib/postgresql/.pgpass
PG_EXPORTER_AUTO_DISCOVER_DATABASES=true
EOF

# Create the systemd service
sudo tee /etc/systemd/system/postgres_exporter.service > /dev/null << 'EOF'
[Unit]
Description=PostgreSQL Metrics Exporter for Prometheus
After=network.target patroni.service

[Service]
Type=simple
User=postgres
Group=postgres
WorkingDirectory=/var/lib/postgresql
EnvironmentFile=/var/lib/postgresql/postgres_exporter.env
ExecStart=/usr/local/bin/postgres_exporter \
  --web.listen-address=:9187 \
  --web.telemetry-path=/metrics
Restart=on-failure
StandardOutput=journal
StandardError=journal
SyslogIdentifier=postgres_exporter

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now postgres_exporter
```

## 9. Open Required Firewall Ports

```bash
sudo firewall-cmd --permanent --add-port=5432/tcp   # PostgreSQL
sudo firewall-cmd --permanent --add-port=8008/tcp   # Patroni REST API
sudo firewall-cmd --permanent --add-port=2379/tcp   # etcd client
sudo firewall-cmd --permanent --add-port=2380/tcp   # etcd peer
sudo firewall-cmd --permanent --add-port=9187/tcp   # postgres_exporter
sudo firewall-cmd --reload
```

## 10. Bootstrap Patroni (Convert Existing Standalone)

> Patroni detects an existing data directory and takes ownership of it without reinitialising.
> Reference: <https://patroni.readthedocs.io/en/latest/existing_data.html>

```bash
# Stop the standalone PostgreSQL service
sudo systemctl stop postgresql-18
sudo systemctl disable postgresql-18

# Start Patroni – it picks up /var/lib/postgresql/18/main as-is
sudo systemctl enable --now patroni

# Follow startup logs
sudo journalctl -u patroni -f
```

## 11. Verify the Single-Node Patroni Cluster

```bash
# List cluster members
sudo -u postgres patronictl -c /var/lib/postgresql/patroni.yml list

# Inspect the Patroni REST API
curl -s http://192.168.100.55:8008 | python3 -m json.tool

# Confirm the node is the leader
curl -s http://192.168.100.55:8008/leader

# Connect to PostgreSQL through Patroni
sudo -u postgres psql -h 192.168.100.55 -p 5432 -d postgres -c "SELECT version();"

# List database roles
sudo -u postgres psql -h 127.0.0.1 -p 5432 -d postgres -c "\du"
```

---

# Add Replicas to the Patroni Cluster

> Perform **Steps 1–4** on **each replica node**. Replace `<REPLICA_IP>` and `<REPLICA_HOSTNAME>` with the actual values for that node.

## 1. Set Up postgres User Home Directory on Replica

```bash
sudo mkdir -p /var/lib/postgresql
sudo usermod -d /var/lib/postgresql -s /bin/bash postgres
sudo chown -R postgres:postgres /var/lib/postgresql

sudo -u postgres mkdir -p /var/lib/postgresql/{18/main,log,scripts}

sudo -u postgres tee /var/lib/postgresql/.bash_profile > /dev/null << 'EOF'
export PATH=/usr/pgsql-18/bin:$PATH
export PGDATA=/var/lib/postgresql/18/main
export PGPORT=5432
export PGPASSFILE=/var/lib/postgresql/.pgpass
EOF
```

## 2. Install PostgreSQL 18, Patroni, and pgbackrest on Replica

```bash
# PGDG repository
sudo dnf install -y \
  https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql
sudo dnf install -y postgresql18-server postgresql18 postgresql18-contrib postgresql18-libs

# Patroni manages PostgreSQL – keep the service disabled
sudo systemctl disable postgresql-18

# Patroni
sudo dnf install -y python3 python3-pip python3-devel gcc
sudo pip3 install patroni[etcd3]

# pgbackrest
sudo dnf install -y pgbackrest
```

## 3. Create .pgpass and patroni.yml on Replica

```bash
# .pgpass – stored in postgres user home
sudo -u postgres tee /var/lib/postgresql/.pgpass > /dev/null << 'EOF'
*:5432:*:postgres:YourSuperUserPassword
*:5432:*:replicator:YourReplicatorPassword
EOF
sudo chmod 0600 /var/lib/postgresql/.pgpass

# patroni.yml – stored in postgres user home
sudo -u postgres tee /var/lib/postgresql/patroni.yml > /dev/null << 'EOF'
scope: postgres-cluster
namespace: /db/
name: <REPLICA_HOSTNAME>

restapi:
  listen: <REPLICA_IP>:8008
  connect_address: <REPLICA_IP>:8008

etcd3:
  hosts: 192.168.100.55:2379

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
        archive_command: "pgbackrest --stanza=sqlred archive-push %p"
        restore_command: "pgbackrest --stanza=sqlred archive-get %f %p"

  pg_hba:
    - "local   all             postgres                            peer"
    - "local   all             all                                 scram-sha-256"
    - "host    all             all             127.0.0.1/32        scram-sha-256"
    - "host    replication     replicator      127.0.0.1/32        scram-sha-256"
    - "host    replication     replicator      192.168.100.0/24    scram-sha-256"
    - "host    all             all             192.168.100.0/24    scram-sha-256"

postgresql:
  listen: "<REPLICA_IP>:5432,127.0.0.1:5432"
  connect_address: "<REPLICA_IP>:5432"
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/pgsql-18/bin
  config_dir: /var/lib/postgresql/18/main
  pgpass: /var/lib/postgresql/.pgpass
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
    log_directory: /var/lib/postgresql/log
    log_filename: "postgresql-%Y-%m-%d_%H%M%S.log"
    logging_collector: "on"

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

sudo chmod 0600 /var/lib/postgresql/patroni.yml
```

## 4. Create Patroni systemd Service and Start on Replica

```bash
sudo tee /etc/systemd/system/patroni.service > /dev/null << 'EOF'
[Unit]
Description=Patroni – High Availability PostgreSQL Cluster Manager
After=syslog.target network.target
Wants=network-online.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /var/lib/postgresql/patroni.yml
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

sudo systemctl daemon-reload

# Open required firewall ports on the replica
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --permanent --add-port=8008/tcp
sudo firewall-cmd --reload

# Start Patroni – it will pg_basebackup from the primary automatically
sudo systemctl enable --now patroni

# Follow the clone + startup progress
sudo journalctl -u patroni -f
```

## 5. Configure pgbackrest on Replica

Each replica needs its own pgbackrest config pointing to the same remote repository on `ryzen9`. SSH trust from this replica's `postgres` user to `ryzen9`'s `postgres` user must also be established (follow the same SSH key exchange procedure from **Step 9** of the *Install PostgreSQL 18 on RHEL* section, substituting this replica's IP).

```bash
# Create /etc/pgbackrest and write the config (requires root)
sudo mkdir -p /etc/pgbackrest

sudo tee /etc/pgbackrest/pgbackrest.conf > /dev/null << 'EOF'
[global]
# Remote repository host (same as primary)
repo1-host=ryzen9
repo1-host-user=postgres
repo1-path=/stale-storage/share-stalestorage/pgbackrest_backups
repo1-retention-full=2
repo1-retention-diff=7
log-level-console=info
log-level-file=detail
log-path=/var/lib/postgresql/log

[sqlred]
pg1-path=/var/lib/postgresql/18/main
pg1-port=5432
pg1-user=postgres
EOF

# Directory must be traversable and file readable by the postgres user
sudo chmod 755 /etc/pgbackrest/
sudo chmod 644 /etc/pgbackrest/pgbackrest.conf
```

## 6. Verify the Replica Joined the Cluster

```bash
# Run from any cluster node
sudo -u postgres patronictl -c /var/lib/postgresql/patroni.yml list

# Expected output:
# + Cluster: postgres-cluster (xxxxxxxxxxxxxxx) ----+----+-----------+
# | Member            | Host                  | Role    | State   | TL | Lag in MB |
# +-------------------+-----------------------+---------+---------+----+-----------+
# | sqlred            | 192.168.100.55:5432   | Leader  | running |  1 |           |
# | <REPLICA_HOSTNAME>| <REPLICA_IP>:5432     | Replica | running |  1 |         0 |
# +-------------------+-----------------------+---------+---------+----+-----------+

# Check streaming replication from the primary
sudo -u postgres psql -h 127.0.0.1 -p 5432 -d postgres \
  -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
```

---

## Useful patronictl Commands

> If `PATRONICTL_CONFIG_FILE=/var/lib/postgresql/patroni.yml` is exported in the postgres user profile, the `-c` flag can be omitted from all commands below.

```bash
# List all cluster members
patronictl list

# Show failover history
patronictl history

# Perform a planned switchover (interactive)
patronictl switchover postgres-cluster

# Initiate an emergency failover to a specific replica
patronictl failover postgres-cluster --master sqlred --candidate <REPLICA_HOSTNAME>

# Reload Patroni configuration without restart
patronictl reload postgres-cluster

# Pause automatic failover (e.g. for maintenance)
patronictl pause postgres-cluster

# Resume automatic failover
patronictl resume postgres-cluster

# Edit DCS-stored cluster configuration
patronictl edit-config postgres-cluster

# Reinitialise a replica (e.g. after data corruption)
patronictl reinit postgres-cluster <REPLICA_HOSTNAME>
```
