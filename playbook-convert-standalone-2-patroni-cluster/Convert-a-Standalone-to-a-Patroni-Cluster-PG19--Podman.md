# Convert a Standalone to a Patroni Cluster — PostgreSQL 19 on Podman Containers

---

## PostgreSQL 19 Key Features

PostgreSQL 19 (Beta 1 released June 4, 2026) introduces significant enhancements for production HA clusters. Full release notes: [postgresql.org/docs/19/release-19.html](https://www.postgresql.org/docs/19/release-19.html)

### Performance Enhancements
- **Parallel vacuum workers**: Autovacuum can now use parallel workers configured via `autovacuum_max_parallel_workers` to speed up maintenance
- **New autovacuum scoring system**: Intelligently prioritizes tables for vacuuming based on multiple factors
- **Automatic I/O worker scaling**: `io_method=worker` now auto-scales based on `io_min_workers` and `io_max_workers`
- **TOAST compression**: Default changed from pglz to lz4 for better compression/decompression performance
- **Query optimization improvements**: Anti-join optimizations, incremental sorts, eager aggregation, faster storage reads during parallel scans
- **Foreign key performance**: Up to 2x faster inserts with foreign key constraints
- **LISTEN/NOTIFY scalability**: Improved for multi-channel workloads

### Replication & Logical Replication
- **WAIT FOR LSN**: Subscribers can wait for specific LSN values to be written, flushed, or replayed before executing queries (enables "read-your-writes" patterns)
- **Sequence synchronization**: Logical replication now replicates sequence values, simplifying online upgrades
- **CREATE PUBLICATION ... EXCEPT**: Publish all tables except a specified set
- **CREATE SUBSCRIPTION ... SERVER**: Define subscriptions using foreign servers for simpler credential management
- **Enable logical replication on-demand**: No longer requires server restart; works with `wal_level=replica`
- **Improved slot synchronization**: Better tracking of replication slot sync status

### Reliability & Data Integrity
- **Online checksum control**: Enable/disable data checksums without cluster restart or reinitialization (major improvement)
- **Password expiration warnings**: New `password_expiration_warning_threshold` setting (defaults to 7 days)
- **MD5 deprecation**: Issues client warnings after successful MD5 authentication (controlled via `md5_password_warnings`)

### Monitoring & Observability
- **New `pg_stat_lock` view**: Per-lock-type statistics for improved lock monitoring
- **New `pg_stat_recovery` view**: Detailed visibility into recovery operations
- **`pg_stat_progress_vacuum`/`pg_stat_progress_analyze`**: Now show initiator and operation mode
- **`stats_reset` column**: Available across many statistics views to track when counters were last cleared
- **Per-process log levels**: `log_min_messages` can now be specified per process type for finer control
- **WAL full page write tracking**: Reported in VACUUM, ANALYZE, and EXPLAIN ANALYZE output
- **EXPLAIN ANALYZE IO option**: New statistics for asynchronous I/O activity

### SQL & Developer Experience
- **SQL/PGQ support**: Property graph queries using SQL standard syntax
- **UPDATE/DELETE FOR PORTION OF**: Temporal query improvements for range operations
- **ALTER TABLE ... MERGE/SPLIT PARTITIONS**: Easier in-place reorganization of partitioned tables
- **INSERT ... ON CONFLICT DO SELECT ... RETURNING**: Retrieve conflicting rows during upserts
- **GROUP BY ALL**: Auto-include all non-aggregate columns in grouping
- **Server-side SNI support**: Via new `pg_hosts.conf` for different TLS certificates per hostname
- **DDL retrieval functions**: `pg_get_role_ddl()`, `pg_get_tablespace_ddl()`, `pg_get_database_ddl()` for easier scripting

### What This Means for Your HA Cluster
- ✅ **Faster failover**: Better vacuum parallelization and anti-join optimizations
- ✅ **Safer operations**: Online checksum control avoids restarts; WAIT FOR LSN enables safe replica reads
- ✅ **Better observability**: New monitoring views give deeper insight into cluster health
- ✅ **Simplified replication**: Sequence sync simplifies logical replication upgrade workflows
- ✅ **Improved performance**: Up to 2x faster foreign key checks and parallel vacuum operations

---

## Setup & Environment

Host (container runtime) — ryzen9 (192.168.100.1), Ubuntu 24.04
Podman network        — lab-network (172.18.0.0/16)
Patroni cluster name  — podpg-cls3
pgbackrest stanza     — podpg-cls3
pgbackrest backup     — bind mount of /stale-storage/share-stalestorage/pgbackrest_backups_cls3 → /mnt/pgbackrest-repo inside each container

| Container        | IP           | SSH (host) | PG (host) | Patroni (host) |
|------------------|--------------|------------|-----------|----------------|
| podpg-cls3-pg1   | 172.18.0.21  | 2231       | 5441      | 8021           |
| podpg-cls3-pg2   | 172.18.0.22  | 2232       | 5442      | 8022           |
| podpg-cls3-pg3   | 172.18.0.23  | 2233       | 5443      | 8023           |
| podpg-cls3-pg4   | 172.18.0.24  | 2234       | 5444      | 8024           |

## Tools
- postgresql 19 (PGDG apt) — [Official installation guide](https://www.postgresql.org/download/linux/ubuntu/)
- patroni latest (pip)
- pgbackrest latest (apt)
- etcd v3.5.17 (binary)

---

## Installation Instructions Validation

All instructions below have been validated against official PostgreSQL 19 documentation:

> **Note**: PostgreSQL 19 is currently in Beta 1 (released June 4, 2026) and is **not available in the PGDG apt repository** yet. All instructions below build PostgreSQL 19 from source using the official tarball from [ftp.postgresql.org/pub/source/v19beta1/](https://ftp.postgresql.org/pub/source/v19beta1/)

Official references:
- **PostgreSQL 19 Build from Source** — [postgres.postgresql.org/docs/devel/installation.html](https://www.postgresql.org/docs/devel/installation.html)
- **initdb command-line options** — [postgres.postgresql.org/docs/devel/app-initdb.html](https://www.postgresql.org/docs/devel/app-initdb.html)
- **pg_hba.conf authentication methods** — [postgres.postgresql.org/docs/devel/auth-pg-hba-conf.html](https://www.postgresql.org/docs/devel/auth-pg-hba-conf.html)

---

## ⚡ Quick Reference: Binary Reuse Strategy

Since PostgreSQL 19 Beta 1 takes **10-15 minutes to build from source**, you have two options:

### Option 1: Build Once, Copy Many (Recommended)
1. Build PostgreSQL 19 on **pg1** (first node) - takes 10-15 min
2. Copy `/usr/local/postgresql-19` to **pg2, pg3, pg4** using `podman cp` - takes ~1 min per node
3. **Total time**: ~20 minutes for entire cluster instead of 40-60 minutes

### Option 2: Build on Each Node
1. Build PostgreSQL 19 on each node independently
2. **Total time**: 40-60 minutes for entire cluster

**Recommended**: Use **Option 1** for faster deployment. Each section below shows both approaches.

---

# Part 1 — Create the Podman Container (podpg-cls3-pg1)

> Run all commands on **ryzen9** (the Podman host) unless noted otherwise.

## 1. Build the base image (skip if `pg-cluster-node:latest` already exists)

```bash
# The Dockerfile is in the cls1 playbook directory — reuse it for cls3
cd playbook-convert-standalone-2-patroni-cluster/

podman build -t pg-cluster-node:latest .

# Verify
podman image ls pg-cluster-node:latest
```

## 2. Prepare the backup directory on the host (one-time setup)

> In rootless Podman, container UIDs are remapped through the subuid range and do not match
> host UIDs. Creating a dedicated, world-writable directory for cls3 avoids UID permission
> conflicts on the bind mount.

```bash
# Run on ryzen9 HOST (not inside container)
sudo mkdir -p /stale-storage/share-stalestorage/pgbackrest_backups_cls3
sudo chmod 777 /stale-storage/share-stalestorage/pgbackrest_backups_cls3

# Verify
ls -la /stale-storage/share-stalestorage/
```

## 3. Create a named volume for PostgreSQL data

```bash
podman volume create pg-cls3-data-pg1
podman volume create pg-cls3-logs-pg1

# Verify
podman volume ls | grep pg-cls3
```

## 4. Create the container

```bash
podman run -d \
  --name podpg-cls3-pg1 \
  --hostname podpg-cls3-pg1 \
  --network lab-network:ip=172.18.0.31 \
  --privileged \
  --cgroupns=host \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  --tmpfs /run \
  --tmpfs /run/lock \
  --volume pg-cls3-data-pg1:/var/lib/postgresql \
  --volume pg-cls3-logs-pg1:/var/log \
  --volume /stale-storage/share-stalestorage/pgbackrest_backups_cls3:/mnt/pgbackrest-repo \
  --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --restart=unless-stopped \
  pg-cluster-node:latest

# Verify it is running
podman ps --filter name=podpg-cls3-pg1
```

## 5. Open a shell inside the container

```bash
podman exec -it podpg-cls3-pg1 bash
# All subsequent commands in Parts 2–5 run INSIDE this shell unless noted.
```

## 5. Add /etc/hosts entries (skip own IP)

```bash
# Run inside podpg-cls3-pg1
cat >> /etc/hosts << 'EOF'
172.18.0.32     podpg-cls3-pg2
172.18.0.33     podpg-cls3-pg3
172.18.0.34     podpg-cls3-pg4
172.18.0.35     podpg-cls3-pg5
172.18.0.36     podpg-cls3-pg6
EOF
```

---

# Part 2 — Install PostgreSQL 19

> Run inside **podpg-cls3-pg1**.

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

## 2. Install PostgreSQL 19 and pgbackrest

```bash
# Install build dependencies for PostgreSQL 19 from source
apt-get update
apt-get install -y \
  build-essential \
  libreadline-dev \
  zlib1g-dev \
  libssl-dev \
  libpam0g-dev \
  libxml2-dev \
  libxslt1-dev \
  libipc-run-perl \
  icu-devtools \
  libicu-dev \
  flex \
  bison \
  uuid-dev \
  libossp-uuid-dev \
  pkg-config \
  pgbackrest \
  python3 python3-pip python3-dev \
  curl wget jq acl less git

# Download PostgreSQL 19 Beta 1 source
cd /tmp
wget -q https://ftp.postgresql.org/pub/source/v19beta1/postgresql-19beta1.tar.gz
tar xzf postgresql-19beta1.tar.gz
cd postgresql-19beta1

# Build and install PostgreSQL 19 from source
mkdir build && cd build
../configure \
  --prefix=/usr/local/postgresql-19 \
  --with-uuid=ossp \
  --with-ssl=openssl \
  --with-pam \
  --with-python \
  --enable-debug \
  --enable-depend \
  --sysconfdir=/etc/postgresql

make -j$(nproc)
make install
make install-contrib

# Create symlinks for easier access
ln -s /usr/local/postgresql-19/bin/* /usr/local/bin/ 2>/dev/null || true

# Verify
postgres --version
pgbackrest version
```

## 3. Set up postgres user home and profile

```bash
# Clear any previous installation
pg_dropcluster --stop 19 main 2>/dev/null || true

# postgres user and /var/lib/postgresql already exist from the package install
mkdir -p /var/lib/postgresql/{19/main,log,scripts}
chown -R postgres:postgres /var/lib/postgresql

sudo -u postgres tee /var/lib/postgresql/.bash_profile > /dev/null << 'EOF'
# PostgreSQL 19 environment (built from source)
export PATH=/usr/local/postgresql-19/bin:$PATH
export PGDATA=/var/lib/postgresql/19/main
export PGPORT=5432
export PGPASSFILE=/var/lib/postgresql/.pgpass
export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
export LD_LIBRARY_PATH=/usr/local/postgresql-19/lib:$LD_LIBRARY_PATH
EOF
```

## 4. Initialize the database with initdb

```bash
# Remove any existing cluster data
rm -rf /var/lib/postgresql/19/main/*

# initdb — configs go into the data dir (consistent with Patroni's expectations)
sudo -u postgres /usr/local/postgresql-19/bin/initdb \
  --encoding=UTF8 \
  --data-checksums \
  --pgdata=/var/lib/postgresql/19/main \
  --auth-local=peer \
  --auth-host=scram-sha-256

ls /var/lib/postgresql/19/main/
```

## 5. Configure postgresql.conf

```bash
sudo -u postgres tee -a /var/lib/postgresql/19/main/postgresql.conf > /dev/null << 'EOF'

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
archive_command = 'pgbackrest --stanza=podpg-cls3 archive-push %p'
restore_command = 'pgbackrest --stanza=podpg-cls3 archive-get %f %p'

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
sudo -u postgres tee /var/lib/postgresql/19/main/pg_hba.conf > /dev/null << 'EOF'
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
*:*:*:replicator:YourReplicatorPassword
EOF

chmod 0750 -R /var/lib/postgresql
chmod 0600 /var/lib/postgresql/.pgpass
```

## 8. Create a systemd service and start PostgreSQL (standalone)

```bash
tee /etc/systemd/system/postgresql-19.service > /dev/null << 'EOF'
[Unit]
Description=PostgreSQL 19 Database Server
After=network.target

[Service]
Type=forking
User=postgres
Group=postgres
Environment=PGDATA=/var/lib/postgresql/19/main
Environment=LD_LIBRARY_PATH=/usr/local/postgresql-19/lib
ExecStart=/usr/local/postgresql-19/bin/pg_ctl start \
  -D /var/lib/postgresql/19/main \
  -l /var/log/postgresql/startup.log
ExecStop=/usr/local/postgresql-19/bin/pg_ctl stop \
  -D /var/lib/postgresql/19/main
ExecReload=/usr/local/postgresql-19/bin/pg_ctl reload \
  -D /var/lib/postgresql/19/main
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable postgresql-19
systemctl start postgresql-19
systemctl status postgresql-19
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

# Part 2 — Build pgbackrest from GitHub and Export PostgreSQL 19 Binaries

> **PostgreSQL 19 Beta 1 requires pgbackrest built from GitHub source** since the apt version (2.58.0) doesn't support PG19 yet.
> The control/catalog versions in PG19 Beta 1 (1902/202605131) are not recognized by pgbackrest 2.58.0.

## Build pgbackrest from Source for PostgreSQL 19

> Run this **inside podpg-cls3-pg1** after PostgreSQL 19 is built.
> pgbackrest uses **Meson** build system (not autotools).

```bash
# Install build dependencies for pgbackrest (Meson-based build)
apt-get update
apt-get install -y \
  meson \
  ninja-build \
  gcc \
  libpq-dev \
  libssl-dev \
  libxml2-dev \
  pkg-config \
  liblz4-dev \
  libzstd-dev \
  libbz2-dev \
  zlib1g-dev \
  libyaml-dev \
  libssh2-1-dev \
  git

# Clone integration branch (has latest features for PostgreSQL 19)
cd /tmp
rm -rf pgbackrest-build pgbackrest-build-dir 2>/dev/null || true
git clone --depth 1 -b integration https://github.com/pgbackrest/pgbackrest.git pgbackrest-build

```

### Complete Build Script (Recommended)

Save this as `/tmp/build-pgbackrest-pg19.sh` and run:

```bash
#!/bin/bash
# Build pgbackrest from integration branch for PostgreSQL 19 Beta 1 support
# Run this as root inside the podpg-cls3-pg1 container

set -e

echo "=== Building pgbackrest from integration branch ==="
echo "Target: /tmp/pgbackrest/"

# Install build dependencies
apt-get update -qq 2>&1 | tail -1
apt-get install -y -qq meson ninja-build gcc libpq-dev libssl-dev libxml2-dev \
  pkg-config liblz4-dev libzstd-dev libbz2-dev zlib1g-dev libyaml-dev libssh2-1-dev git 2>&1 | tail -1

# Clone integration branch (better PG19 support)
PGBACKREST_SRC="/tmp/pgbackrest-src"
PGBACKREST_BUILD="/tmp/pgbackrest-build"
PGBACKREST_INSTALL="/tmp/pgbackrest-install"

rm -rf "$PGBACKREST_SRC" "$PGBACKREST_BUILD" "$PGBACKREST_INSTALL" 2>/dev/null || true
mkdir -p "$PGBACKREST_SRC" "$PGBACKREST_BUILD" "$PGBACKREST_INSTALL"

echo "Cloning integration branch..."
git clone --depth 1 -b integration https://github.com/pgbackrest/pgbackrest.git "$PGBACKREST_SRC" 2>&1 | tail -2

# Build using Meson
echo "Configuring with Meson..."
meson setup "$PGBACKREST_BUILD" "$PGBACKREST_SRC" --prefix="$PGBACKREST_INSTALL" 2>&1 | tail -5
echo "Building with Ninja..."
ninja -C "$PGBACKREST_BUILD" 2>&1 | tail -3
echo "Installing..."
ninja -C "$PGBACKREST_BUILD" install 2>&1 | tail -2

# Verify
echo "Verifying pgbackrest..."
$PGBACKREST_INSTALL/bin/pgbackrest --version

# Create tarball for distribution
mkdir -p /tmp/pgbackrest
tar czf /tmp/pgbackrest/pgbackrest-pg19.tar.gz -C "$PGBACKREST_INSTALL/bin" pgbackrest

echo "=== Build Complete ==="
ls -lh /tmp/pgbackrest/pgbackrest-pg19.tar.gz
echo "Binary: $PGBACKREST_INSTALL/bin/pgbackrest"
```

**To run this script inside the container:**

```bash
bash /tmp/build-pgbackrest-pg19.sh
cp /tmp/pgbackrest-install/bin/pgbackrest /usr/bin/
pgbackrest --version
```

### Manual Step-by-Step (Alternative)

If you prefer to run commands manually:

```bash
# Step 1: Install build dependencies
apt-get update
apt-get install -y meson ninja-build gcc libpq-dev libssl-dev libxml2-dev \
  pkg-config liblz4-dev libzstd-dev libbz2-dev zlib1g-dev libyaml-dev libssh2-1-dev git

# Step 2: Clone integration branch
cd /tmp
rm -rf pgbackrest-src pgbackrest-build pgbackrest-install 2>/dev/null || true
git clone --depth 1 -b integration https://github.com/pgbackrest/pgbackrest.git pgbackrest-src

# Step 3: Configure with Meson
mkdir -p pgbackrest-build pgbackrest-install
meson setup pgbackrest-build pgbackrest-src --prefix=/tmp/pgbackrest-install

# Step 4: Build with Ninja
ninja -C pgbackrest-build

# Step 5: Install
ninja -C pgbackrest-build install

# Step 6: Verify
/tmp/pgbackrest-install/bin/pgbackrest --version

# Step 7: Create tarball for distribution to other nodes
mkdir -p /tmp/pgbackrest
tar czf /tmp/pgbackrest/pgbackrest-pg19.tar.gz -C /tmp/pgbackrest-install/bin pgbackrest

# Step 8: Verify tarball
ls -lh /tmp/pgbackrest/pgbackrest-pg19.tar.gz
```

### Copy to Host Storage (on ryzen9 host after building in container)

```bash
# From host (ryzen9), copy tarball to persistent storage
podman cp podpg-cls3-pg1:/tmp/pgbackrest/pgbackrest-pg19.tar.gz /stale-storage/Softwares/PostgreSQL/postgresql-19-backup/

# Verify
ls -lh /stale-storage/Softwares/PostgreSQL/postgresql-19-backup/pgbackrest-pg19.tar.gz

# Files are present on ryzen9 on /stale-storage/Softwares/PostgreSQL/postgresql-19-backup/
```

## Export PostgreSQL 19 Binaries from pg1 (Optional but Recommended)

> **If you built PostgreSQL 19 on pg1 and want to skip rebuilding on pg2/pg4, use this section.**
> This saves ~20-25 minutes of compile time on other nodes.

## Copy binaries from pg1 to host

Run these commands **on the host (ryzen9)** after pg1 is built:

```bash
# Option 1: Export as tarball (useful if you have many nodes or want to archive)
podman exec podpg-cls3-pg1 tar czf /tmp/postgresql-19-binaries.tar.gz -C /usr/local postgresql-19

podman cp podpg-cls3-pg1:/tmp/postgresql-19-binaries.tar.gz /tmp/
podman cp podpg-cls3-pg1:/tmp/pgbackrest/pgbackrest-pg19.tar.gz /tmp/

# Verify the tarball size (should be ~100-200 MB)
ls -lh /tmp/postgresql-19-binaries.tar.gz
ls -lh /tmp/pgbackrest-pg19.tar.gz

# Option 2: Copy directory directly (fastest)
mkdir -p /tmp/postgresql-19-backup
podman cp podpg-cls3-pg1:/usr/local/postgresql-19 /tmp/postgresql-19-backup/

# Files are present on ryzen9 on /stale-storage/Softwares/PostgreSQL/postgresql-19-backup/
```

## Verify binaries are usable

```bash
# Test the binaries work
/tmp/postgresql-19-backup/postgresql-19/bin/postgres --version

# Check dependencies
ldd /tmp/postgresql-19-backup/postgresql-19/bin/postgres | head -10
```

---

## Install pgbackrest on pg2 and pg4 (Optional - Reuse from pg1)

> If you want to avoid building pgbackrest on every node, copy the binary from pg1.

**On pg2 and pg4:**

```bash
# Option A: Install from tarball (if you created pgbackrest-pg19.tar.gz)
cd /tmp
tar xzf /path/to/pgbackrest-pg19.tar.gz -C /usr/local/bin

# Option B: Copy pgbackrest binary from pg1 container (fastest)
mkdir -p /tmp/pgbackrest-dist
podman cp podpg-cls3-pg1:/usr/local/bin/pgbackrest /tmp/pgbackrest-dist/
cp /tmp/pgbackrest-dist/pgbackrest /usr/local/bin/
chmod 755 /usr/local/bin/pgbackrest

# Option C: Build from GitHub on this node (takes ~10-15 min)
apt-get update
apt-get install -y meson ninja-build gcc libpq-dev libssl-dev libxml2-dev pkg-config liblz4-dev libzstd-dev libbz2-dev zlib1g-dev libyaml-dev libssh2-1-dev git
cd /tmp && git clone --depth 1 https://github.com/pgbackrest/pgbackrest.git pgbackrest-build-$$
mkdir -p /tmp/pgbackrest-build-dir-$$
meson setup /tmp/pgbackrest-build-dir-$$ /tmp/pgbackrest-build-$$
ninja -C /tmp/pgbackrest-build-dir-$$
ninja -C /tmp/pgbackrest-build-dir-$$ install

# Verify
pgbackrest version
```

---

# Part 3 — Configure pgbackrest (Method 02: Host Bind Mount)

> Run inside **podpg-cls3-pg1**.
> The host directory `/stale-storage/share-stalestorage/pgbackrest_backups_cls3` is bind-mounted
> into every container at `/mnt/pgbackrest-repo` via the `--volume` flag at container creation.
> No CIFS, no Samba, no network mount needed inside the container.

## 1. Verify the bind mount is active

```bash
# Should show the host's backup directory contents
ls -la /mnt/pgbackrest-repo

# Verify postgres can write and delete
sudo -u postgres bash -c 'touch /mnt/pgbackrest-repo/test && echo "Write OK" && rm /mnt/pgbackrest-repo/test && echo "Delete OK"'
```

## 2. Configure pgbackrest.conf

```bash
mkdir -p /etc/pgbackrest

tee /etc/pgbackrest/pgbackrest.conf > /dev/null << 'EOF'
[global]
# Host directory bind-mounted into the container at /var/lib/pgbackrest
repo1-path=/mnt/pgbackrest-repo
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

[podpg-cls3]
pg1-path=/var/lib/postgresql/19/main
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
pgbackrest --stanza=podpg-cls3 stanza-create

# End-to-end config check
pgbackrest --stanza=podpg-cls3 check

# First full backup
pgbackrest --stanza=podpg-cls3 --type=full backup

# Confirm
pgbackrest --stanza=podpg-cls3 info
EOF
```

---

# Part 4 — Convert Standalone to Patroni (Single Node)

> Run inside **podpg-cls3-pg1**.

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
ETCD_NAME="podpg-cls3-pg1"
ETCD_DATA_DIR="/var/lib/etcd"

ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://172.18.0.21:2379"

ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://172.18.0.21:2380"

ETCD_INITIAL_CLUSTER="podpg-cls3-pg1=http://172.18.0.21:2380"
ETCD_INITIAL_CLUSTER_TOKEN="podpg-cls3-etcd"
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
scope: podpg-cls3
namespace: /db/
name: podpg-cls3-pg1

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
        archive_command: "pgbackrest --stanza=podpg-cls3 archive-push %p"
        restore_command: "pgbackrest --stanza=podpg-cls3 archive-get %f %p"

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
  data_dir: /var/lib/postgresql/19/main
  bin_dir: /usr/local/postgresql-19/bin
  config_dir: /var/lib/postgresql/19/main
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
systemctl stop postgresql-19
systemctl disable postgresql-19

# Start Patroni — it adopts /var/lib/postgresql/19/main as-is
systemctl enable --now patroni

systemctl status patroni

# Follow startup
journalctl -u patroni -f
```

## 7. Verify single-node cluster

```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml restart podpg-cls3 --force

# Expected: Role = Leader
curl -s http://172.18.0.21:8008 | python3 -m json.tool
curl -s http://172.18.0.21:8008/leader

sudo -u postgres psql -h 127.0.0.1 -p 5432 -d postgres -c "SELECT version();"
sudo -u postgres psql -h 127.0.0.1 -p 5432 -d postgres -c "\du"
```

---

# Part 5 — Add Replicas (podpg-cls3-pg2 and podpg-cls3-pg3)

> Perform all steps for each replica. Commands marked **[host]** run on ryzen9; all others run **inside the container**.

## podpg-cls3-pg2 (172.18.0.22)

### [host] Create volumes and container

```bash
podman volume create pg-cls3-data-pg2
podman volume create pg-cls3-logs-pg2

podman run -d \
  --name podpg-cls3-pg2 \
  --hostname podpg-cls3-pg2 \
  --network lab-network:ip=172.18.0.22 \
  --privileged \
  --cgroupns=host \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  --tmpfs /run \
  --tmpfs /run/lock \
  --volume pg-cls3-data-pg2:/var/lib/postgresql \
  --volume pg-cls3-logs-pg2:/var/log \
  --volume /stale-storage/share-stalestorage/pgbackrest_backups_cls3:/mnt/pgbackrest-repo \
  --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --restart=unless-stopped \
  pg-cluster-node:latest

podman exec -it podpg-cls3-pg2 bash
```

### [inside podpg-cls3-pg2] /etc/hosts

```bash
cat >> /etc/hosts << 'EOF'
172.18.0.21     podpg-cls3-pg1
172.18.0.22     podpg-cls3-pg2
172.18.0.23     podpg-cls3-pg3
172.18.0.24     podpg-cls3-pg4
172.18.0.25     podpg-cls3-pg5
172.18.0.26     podpg-cls3-pg6
EOF
```

### [inside podpg-cls3-pg2] Install packages

> **OPTION A**: Build from source (takes ~10-15 minutes)
> **OPTION B**: Copy pre-built binaries from pg1 (faster, requires pg1 to be built first)

**Option A: Build from Source**

```bash
apt-get update

# Install build dependencies for PostgreSQL 19 from source
apt-get install -y \
  build-essential \
  libreadline-dev \
  zlib1g-dev \
  libssl-dev \
  libpam0g-dev \
  libxml2-dev \
  libxslt1-dev \
  libipc-run-perl \
  icu-devtools \
  libicu-dev \
  flex \
  bison \
  uuid-dev \
  libossp-uuid-dev \
  pkg-config \
  pgbackrest \
  python3 python3-pip python3-dev \
  curl wget jq acl less git

# Download and build PostgreSQL 19 Beta 1 from source
if [ ! -d /usr/local/postgresql-19 ]; then
  cd /tmp
  wget -q https://ftp.postgresql.org/pub/source/v19beta1/postgresql-19beta1.tar.gz
  tar xzf postgresql-19beta1.tar.gz
  cd postgresql-19beta1

  mkdir build && cd build
  ../configure \
    --prefix=/usr/local/postgresql-19 \
    --with-uuid=ossp \
    --with-ssl=openssl \
    --with-pam \
    --with-python \
    --sysconfdir=/etc/postgresql

  make -j$(nproc)
  make install
  make install-contrib

  ln -sf /usr/local/postgresql-19/bin/* /usr/local/bin/ 2>/dev/null || true
  ln -sf /usr/local/postgresql-19/lib/* /usr/local/lib/ 2>/dev/null || true
fi

mkdir -p /var/lib/postgresql/{19/main,log,scripts}
```

**Option B: Copy Pre-built Binaries from pg1**

> Use this if pg1 has already been built. This is **much faster** and avoids recompiling.

```bash
apt-get update

# Install only runtime dependencies (no build tools needed)
apt-get install -y \
  libreadline8 \
  zlib1g \
  libssl3 \
  libpam0g \
  libxml2 \
  libxslt1.1 \
  libicu72 \
  pgbackrest \
  python3 python3-pip python3-dev \
  curl wget jq acl less

# Copy pre-built PostgreSQL 19 binaries from pg1
mkdir -p /usr/local/postgresql-19

# Method 1: Use podman cp to copy from pg1 container
podman cp podpg-cls3-pg1:/usr/local/postgresql-19 /usr/local/

# OR Method 2: If using network access to pg1
# scp -r -P 2221 root@172.18.0.21:/usr/local/postgresql-19 /usr/local/

# Create symlinks for easier access
ln -sf /usr/local/postgresql-19/bin/* /usr/local/bin/ 2>/dev/null || true
ln -sf /usr/local/postgresql-19/lib/* /usr/local/lib/ 2>/dev/null || true

# Verify
postgres --version

mkdir -p /var/lib/postgresql/{19/main,log,scripts}
```

**Continue with both options:**

```bash
chown -R postgres:postgres /var/lib/postgresql
chmod -R 0750 /var/lib/postgresql

sudo -u postgres tee /var/lib/postgresql/.bash_profile > /dev/null << 'EOF2'
export PATH=/usr/local/postgresql-19/bin:$PATH
export PGDATA=/var/lib/postgresql/19/main
export PGPORT=5432
export PGPASSFILE=/var/lib/postgresql/.pgpass
export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
export LD_LIBRARY_PATH=/usr/local/postgresql-19/lib:$LD_LIBRARY_PATH
EOF2

sudo -u postgres tee /var/lib/postgresql/.pgpass > /dev/null << 'EOF2'
*:*:*:postgres:YourSuperUserPassword
*:5432:*:replicator:YourReplicatorPassword
EOF2

chmod 0750 -R /var/lib/postgresql
chmod 0600 /var/lib/postgresql/.pgpass
```

### [inside podpg-cls3-pg2] Install etcd and Patroni

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

### [inside podpg-cls3-pg2] Configure etcd (joins pg1)

```bash
useradd --system --no-create-home --shell /sbin/nologin etcd 2>/dev/null || true
mkdir -p /etc/etcd /var/lib/etcd

tee /etc/etcd/etcd.conf > /dev/null << 'EOF'
ETCD_NAME="podpg-cls3-pg2"
ETCD_DATA_DIR="/var/lib/etcd"

ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://172.18.0.22:2379"

ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://172.18.0.22:2380"

ETCD_INITIAL_CLUSTER="podpg-cls3-pg1=http://172.18.0.21:2380,podpg-cls3-pg2=http://172.18.0.22:2380"
ETCD_INITIAL_CLUSTER_TOKEN="podpg-cls3-etcd"
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
# Run this on podpg-cls3-pg1
etcdctl --endpoints=http://172.18.0.21:2379 \
  member add podpg-cls3-pg2 --peer-urls=http://172.18.0.22:2380
```

```bash
# Back on podpg-cls3-pg2
systemctl enable --now etcd
etcdctl --endpoints=http://172.18.0.21:2379,http://172.18.0.22:2379 member list
```

### [inside podpg-cls3-pg2] Configure pgbackrest

> The host backup directory is already available at `/var/lib/pgbackrest` via the bind mount
> set in the container creation command. No mount needed inside the container.

```bash
mkdir -p /etc/pgbackrest
tee /etc/pgbackrest/pgbackrest.conf > /dev/null << 'EOF'
[global]
repo1-path=/mnt/pgbackrest-repo
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

[podpg-cls3]
pg1-path=/var/lib/postgresql/19/main
pg1-port=5432
pg1-user=postgres
EOF

chmod 755 /etc/pgbackrest/
chmod 644 /etc/pgbackrest/pgbackrest.conf
mkdir -p /var/log/pgbackrest /var/spool/pgbackrest
chown postgres:postgres /var/log/pgbackrest /var/spool/pgbackrest
```

### [inside podpg-cls3-pg2] Configure Patroni and join the cluster

```bash
mkdir -p /etc/patroni

tee /etc/patroni/patroni.yml > /dev/null << 'EOF'
scope: podpg-cls3
namespace: /db/
name: podpg-cls3-pg2

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
        archive_command: "pgbackrest --stanza=podpg-cls3 archive-push %p"
        restore_command: "pgbackrest --stanza=podpg-cls3 archive-get %f %p"

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
  data_dir: /var/lib/postgresql/19/main
  bin_dir: /usr/local/postgresql-19/bin
  config_dir: /var/lib/postgresql/19/main
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

## podpg-cls3-pg3 (172.18.0.23)

Repeat the same steps as podpg-cls3-pg2 with these substitutions:

| Item | pg2 value | pg3 value |
|------|-----------|-----------|
| Container name | podpg-cls3-pg2 | podpg-cls3-pg3 |
| IP | 172.18.0.22 | 172.18.0.23 |
| Volume names | pg-cls3-data-pg2, pg-cls3-logs-pg2 | pg-cls3-data-pg3, pg-cls3-logs-pg3 |
| ETCD_NAME | podpg-cls3-pg2 | podpg-cls3-pg3 |
| ETCD_ADVERTISE_CLIENT_URLS | http://172.18.0.22:2379 | http://172.18.0.23:2379 |
| ETCD_INITIAL_ADVERTISE_PEER_URLS | http://172.18.0.22:2380 | http://172.18.0.23:2380 |
| ETCD_INITIAL_CLUSTER | pg1+pg2 | pg1+pg2+pg3 |
| /etc/hosts skips | pg2 entry | pg3 entry |

**Add pg3 member to etcd on pg1 before starting etcd on pg3:**

```bash
# On podpg-cls3-pg1
etcdctl --endpoints=http://172.18.0.21:2379,http://172.18.0.22:2379 \
  member add podpg-cls3-pg3 --peer-urls=http://172.18.0.23:2380
```

**etcd.conf ETCD_INITIAL_CLUSTER for pg3:**
```
ETCD_INITIAL_CLUSTER="podpg-cls3-pg1=http://172.18.0.21:2380,podpg-cls3-pg2=http://172.18.0.22:2380,podpg-cls3-pg3=http://172.18.0.23:2380"
ETCD_INITIAL_CLUSTER_STATE="existing"
```

---

# Part 6 — Verify the 3-Node Cluster

```bash
# From any node
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list

# Expected output:
# + Cluster: podpg-cls3 (xxxxxxxxxxxxxxx) ----+----+-----------+
# | Member           | Host            | Role    | State   | TL | Lag in MB |
# +------------------+-----------------+---------+---------+----+-----------+
# | podpg-cls3-pg1   | 172.18.0.21:5432| Leader  | running |  1 |           |
# | podpg-cls3-pg2   | 172.18.0.22:5432| Replica | running |  1 |         0 |
# | podpg-cls3-pg3   | 172.18.0.23:5432| Replica | running |  1 |         0 |
# +------------------+-----------------+---------+---------+----+-----------+

# Check etcd cluster health
etcdctl \
  --endpoints=http://172.18.0.21:2379,http://172.18.0.22:2379,http://172.18.0.23:2379 \
  endpoint health

# Check streaming replication from primary
sudo -u postgres psql -h 127.0.0.1 -p 5432 -d postgres \
  -c "SELECT client_addr, state, sent_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"

# Verify backups
podman exec podpg-cls3-pg1 pgbackrest --stanza=podpg-cls3 info
```

---

# Part 7 — Edit the 3-Node Cluster to have one synchronous replica

```bash
# Enable synchronous mode — one replica becomes Sync Standby
patronictl -c /etc/patroni/patroni.yml edit-config podpg-cls3 \
  --force --set synchronous_mode=true --set synchronous_node_count=1
```

---

# Part 8 — Update podpg-cls3-pg3 to be `nofailover` but allow to be sync standby

```bash
# Tag podpg-cls3-pg3 as nosync + nofailover
# Per-node tags are LOCAL settings — edit patroni.yml on pg3 directly, then reload.
#
# On podpg-cls3-pg3
vim /etc/patroni/patroni.yml

tags:
  nofailover: true
  nosync: false


systemctl restart patroni
```

---

# Part 9 — Set up podpg-cls3-pg4 as a Standby Cluster

> `podpg-cls3-pg4` runs in **Patroni standby cluster mode**. It streams WAL from the
> primary cluster leader (`podpg-cls3-pg1`, 172.18.0.21) and remains read-only until
> explicitly promoted. It has its **own single-node etcd** — it does **not** join the
> pg1/pg2/pg3 etcd cluster.
>
> Commands marked **[host]** run on **ryzen9**; all others run **inside the container**.

## Key Differences from pg2/pg3

| Feature                  | pg2 / pg3 (primary-cluster replicas) | pg4 (standby cluster)              |
|--------------------------|--------------------------------------|------------------------------------|
| etcd                     | Shared 3-node cluster (pg1+pg2+pg3)  | Own single-node etcd on pg4        |
| Patroni scope            | podpg-cls3                           | podpg-cls3 (same — enables failback)|
| Streams from             | Primary cluster leader               | Primary cluster leader (172.18.0.21)|
| `standby_cluster` block  | Not set                              | Set — host: 172.18.0.21, port: 5432|
| Write queries            | Via leader only                      | Read-only until promoted           |

---

## [host] Create volumes and container

```bash
podman volume create pg-cls3-data-pg4
podman volume create pg-cls3-logs-pg4

podman run -d \
  --name podpg-cls3-pg4 \
  --hostname podpg-cls3-pg4 \
  --network lab-network:ip=172.18.0.24 \
  --privileged \
  --cgroupns=host \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  --tmpfs /run \
  --tmpfs /run/lock \
  --volume pg-cls3-data-pg4:/var/lib/postgresql \
  --volume pg-cls3-logs-pg4:/var/log \
  --volume /stale-storage/share-stalestorage/pgbackrest_backups_cls3:/mnt/pgbackrest-repo \
  --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --restart=unless-stopped \
  pg-cluster-node:latest

# Verify container is up
podman ps --filter name=podpg-cls3-pg4

podman exec -it podpg-cls3-pg4 bash
```

---

## [inside podpg-cls3-pg4] /etc/hosts

```bash
cat >> /etc/hosts << 'EOF'
172.18.0.21     podpg-cls3-pg1
172.18.0.22     podpg-cls3-pg2
172.18.0.23     podpg-cls3-pg3
172.18.0.24     podpg-cls3-pg4
172.18.0.25     podpg-cls3-pg5
172.18.0.26     podpg-cls3-pg6
EOF
```

---

## [inside podpg-cls3-pg4] Install packages

> **OPTION A**: Build from source (takes ~10-15 minutes)
> **OPTION B**: Copy pre-built binaries from pg1 (faster, requires pg1 to be built first)

**Option A: Build from Source**

```bash
apt-get update

# Install build dependencies for PostgreSQL 19 from source
apt-get install -y \
  build-essential \
  libreadline-dev \
  zlib1g-dev \
  libssl-dev \
  libpam0g-dev \
  libxml2-dev \
  libxslt1-dev \
  libipc-run-perl \
  icu-devtools \
  libicu-dev \
  flex \
  bison \
  uuid-dev \
  libossp-uuid-dev \
  pkg-config \
  pgbackrest \
  python3 python3-pip python3-dev \
  curl wget jq acl less vim git

# Download and build PostgreSQL 19 Beta 1 from source
if [ ! -d /usr/local/postgresql-19 ]; then
  cd /tmp
  wget -q https://ftp.postgresql.org/pub/source/v19beta1/postgresql-19beta1.tar.gz
  tar xzf postgresql-19beta1.tar.gz
  cd postgresql-19beta1

  mkdir build && cd build
  ../configure \
    --prefix=/usr/local/postgresql-19 \
    --with-uuid=ossp \
    --with-ssl=openssl \
    --with-pam \
    --with-python \
    --sysconfdir=/etc/postgresql

  make -j$(nproc)
  make install
  make install-contrib

  ln -sf /usr/local/postgresql-19/bin/* /usr/local/bin/ 2>/dev/null || true
  ln -sf /usr/local/postgresql-19/lib/* /usr/local/lib/ 2>/dev/null || true
fi

mkdir -p /var/lib/postgresql/{19/main,log,scripts}
```

**Option B: Copy Pre-built Binaries from pg1**

> Use this if pg1 has already been built. This is **much faster** and avoids recompiling.

```bash
apt-get update

# Install only runtime dependencies (no build tools needed)
apt-get install -y \
  libreadline8 \
  zlib1g \
  libssl3 \
  libpam0g \
  libxml2 \
  libxslt1.1 \
  libicu72 \
  pgbackrest \
  python3 python3-pip python3-dev \
  curl wget jq acl less vim

# Copy pre-built PostgreSQL 19 binaries from pg1
mkdir -p /usr/local/postgresql-19

# Method 1: Use podman cp to copy from pg1 container
podman cp podpg-cls3-pg1:/usr/local/postgresql-19 /usr/local/

# OR Method 2: If using network access to pg1
# scp -r -P 2221 root@172.18.0.21:/usr/local/postgresql-19 /usr/local/

# Create symlinks for easier access
ln -sf /usr/local/postgresql-19/bin/* /usr/local/bin/ 2>/dev/null || true
ln -sf /usr/local/postgresql-19/lib/* /usr/local/lib/ 2>/dev/null || true

# Verify
postgres --version

mkdir -p /var/lib/postgresql/{19/main,log,scripts}
```

**Continue with both options:**

```bash
chown -R postgres:postgres /var/lib/postgresql
chmod -R 0750 /var/lib/postgresql

sudo -u postgres tee /var/lib/postgresql/.bash_profile > /dev/null << 'EOF2'
export PATH=/usr/local/postgresql-19/bin:$PATH
export PGDATA=/var/lib/postgresql/19/main
export PGPORT=5432
export PGPASSFILE=/var/lib/postgresql/.pgpass
export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
export LD_LIBRARY_PATH=/usr/local/postgresql-19/lib:$LD_LIBRARY_PATH
EOF2

sudo -u postgres tee /var/lib/postgresql/.pgpass > /dev/null << 'EOF2'
*:*:*:postgres:YourSuperUserPassword
*:5432:*:replicator:YourReplicatorPassword
EOF2

chmod 0750 -R /var/lib/postgresql
chmod 0600 /var/lib/postgresql/.pgpass
```

---

## [inside podpg-cls3-pg4] Install etcd and Patroni

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
ETCD_NAME="podpg-cls3-pg4"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://172.18.0.24:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://172.18.0.24:2380"
ETCD_INITIAL_CLUSTER="podpg-cls3-pg4=http://172.18.0.24:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="podpg-cls3-etcd"
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

## [inside podpg-cls3-pg4] Configure pgbackrest

> pg4 uses the same shared backup repository as pg1/pg2/pg3 (read-only for restore).
> No stanza-create is needed — the stanza already exists on the shared mount.

```bash
mkdir -p /etc/pgbackrest

tee /etc/pgbackrest/pgbackrest.conf > /dev/null << 'EOF'
[global]
# Host directory bind-mounted into the container at /var/lib/pgbackrest
repo1-path=/mnt/pgbackrest-repo
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

[podpg-cls3]
pg1-path=/var/lib/postgresql/19/main
pg1-port=5432
pg1-user=postgres
EOF

chmod 755 /etc/pgbackrest/
chmod 644 /etc/pgbackrest/pgbackrest.conf
mkdir -p /var/log/pgbackrest /var/spool/pgbackrest
chown postgres:postgres /var/log/pgbackrest /var/spool/pgbackrest
```

---

## [inside podpg-cls3-pg4] Configure Patroni (standby cluster mode)

```bash
mkdir -p /etc/patroni

tee /etc/patroni/patroni.yml > /dev/null << 'EOF'
scope: podpg-cls3
namespace: /db/
name: podpg-cls3-pg4

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
        archive_command: "pgbackrest --stanza=podpg-cls3 archive-push %p"
        restore_command: "pgbackrest --stanza=podpg-cls3 archive-get %f %p"

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
  data_dir: /var/lib/postgresql/19/main
  bin_dir: /usr/local/postgresql-19/bin
  config_dir: /var/lib/postgresql/19/main
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

# Start Patroni — it will pg_basebackup from podpg-cls3-pg1 automatically
systemctl enable --now patroni

# Follow clone + startup progress
journalctl -u patroni -f
```

---

## Verify the Standby Cluster

```bash
# From podpg-cls3-pg4 — check Patroni sees it as Standby Leader
patronictl -c /etc/patroni/patroni.yml list
# Expected:
# + Cluster: podpg-cls3 (standby) ---+----------------+----+-----+
# | Member         | Host        | Role           | State     | TL | Lag |
# +----------------+-------------+----------------+-----------+----+-----+
# | podpg-cls3-pg4 | 172.18.0.24 | Standby Leader | streaming |  N |   0 |

# From podpg-cls3-pg1 — confirm pg4 appears as a streaming replica
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
# On podpg-cls3-pg4 — promote the standby to become an autonomous primary
patronictl -c /etc/patroni/patroni.yml edit-config podpg-cls3 \
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
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml switchover podpg-cls3

# Reinitialize a replica
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml reinit podpg-cls3 podpg-cls3-pg2

# Pause / resume automatic failover
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml pause  podpg-cls3
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml resume podpg-cls3

# Edit DCS-stored cluster config
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml edit-config podpg-cls3

# pgbackrest — full backup (run on leader)
podman exec podpg-cls3-pg1 sudo -u postgres \
  pgbackrest --stanza=podpg-cls3 --type=full backup

# pgbackrest — show backup info
podman exec podpg-cls3-pg1 pgbackrest --stanza=podpg-cls3 info

# Connect to cluster via host port
psql -h 127.0.0.1 -p 5441 -U postgres -d postgres   # pg1
psql -h 127.0.0.1 -p 5442 -U postgres -d postgres   # pg2
psql -h 127.0.0.1 -p 5443 -U postgres -d postgres   # pg3
```

