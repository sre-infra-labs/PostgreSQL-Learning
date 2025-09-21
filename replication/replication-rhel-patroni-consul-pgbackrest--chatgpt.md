Awesome — below is a **complete, copy-pasteable runbook** to set up **PostgreSQL physical HADR (streaming replication)** using **Patroni + Consul + pgBackRest** for your three nodes:

| Node Name       | IP Address     | Role              |
| --------------- | -------------- | ----------------- |
| `pg-cls2-prod0` | 192.168.100.47 | Primary / Replica |
| `pg-cls2-prod1` | 192.168.100.48 | Replica           |
| `pg-cls2-prod2` | 192.168.100.49 | Replica           |


This runbook covers **RHEL/CentOS** style commands (adjust `dnf/apt` where needed), and gives full config files and commands. Replace placeholders (`<...>`) with real values (passwords, backup host IP, binary paths).

---

## 0 — High level architecture & assumptions

* **Consul**: you already run a Consul server at `192.168.100.41`. Patroni will use Consul as DCS.
* **Patroni**: cluster manager that performs leader election and automatic failover.
* **PostgreSQL**: version **16** on all nodes (ensure same major version).
* **pgBackRest**: manages backups + WAL archive. We recommend a **central backup host** (`<BACKUP_HOST_IP>`). A local repo option is included for quick testing.
* `postgres` OS user used to run postgres & patroni.
* You have root/sudo on all nodes.

---

## 1 — Quick checklist before starting

* All nodes can reach Consul server `192.168.100.41:8500`.
* All nodes have time sync (chrony/ntp).
* Ports open: **5432** (Postgres), **8008** (Patroni REST), **8500** (Consul client uses 8500 to server), **8600** (Consul DNS optional).
* Same PostgreSQL major version packages installed on all nodes.
* `pg_rewind` binary available (package `postgresql16-rewind` or included in PG distribution).

---

## 2 — Install prerequisites (run on each PG host)

```bash
# as root
dnf -y install python3 python3-venv python3-pip gcc libpq-devel \
               wget tar rsync policycoreutils-python-utils

# PGDG repo & PostgreSQL 16 packages (RHEL/CentOS example)
dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -y module disable postgresql
dnf -y install postgresql16-server postgresql16-contrib postgresql16-devel postgresql16-rewind

# pgBackRest (on PG nodes and backup host if needed)
dnf -y install pgbackrest

# Create Python venv and install Patroni (recommended)
python3 -m venv /opt/patroni-venv
/opt/patroni-venv/bin/pip install --upgrade pip
/opt/patroni-venv/bin/pip install "patroni[consul]" psycopg[binary]
```

> If you prefer OS packages for Patroni, use distro packages. venv avoids packaging traps.

---

## 3 — Create required dirs & user permissions (each node)

```bash
# run as root
useradd --system --home /var/lib/pgsql --shell /bin/bash postgres || true

mkdir -p /etc/patroni /var/lib/postgresql /var/log/patroni /etc/consul.d /var/lib/consul /var/lib/pgbackrest
chown -R postgres:postgres /etc/patroni /var/lib/postgresql /var/log/patroni /var/lib/pgbackrest
```

---

## 4 — Configure Consul client (each node)

Create `/etc/consul.d/client.hcl` (adjust `node_name`, bind/advertise IPs):

**/etc/consul.d/client.hcl**

```hcl
datacenter = "dc1"
data_dir = "/var/lib/consul"
node_name = "pg-cls2-prod0"    # change per node: pg-cls2-prod1, pg-cls2-prod2
bind_addr = "192.168.100.47"
advertise_addr = "192.168.100.47"
client_addr = "127.0.0.1"
retry_join = ["192.168.100.41"]
server = false
```

Start Consul client (if consul installed):

```bash
systemctl daemon-reload
systemctl enable --now consul
```

Verify on Consul server:

```bash
# on consul server:
consul members
```

> If your Consul uses TLS/ACLs, adjust client config for TLS and token.

---

## 5 — pgBackRest: recommended central repository (preferred)

**On backup host** (example `192.168.100.50`), set up repo:

```bash
dnf -y install pgbackrest
useradd --system --home /var/lib/pgbackrest --shell /sbin/nologin pgbackrest || true
mkdir -p /var/lib/pgbackrest
chown -R pgbackrest:pgbackrest /var/lib/pgbackrest
```

Create `/etc/pgbackrest/pgbackrest.conf` on backup host:

```ini
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
repo1-retention-diff=3
log-level-console=info

[main]
pg1-path=/var/lib/postgresql/16/main
```

**If you must test quickly** without a backup host, use local repo on each PG node (see QuickTest section below).

---

## 6 — Patroni configuration — 1 file per node

We’ll produce 3 node-specific `patroni.yml` files. Keep sensitive passwords out of world-readable files (file perms 600).

Common variables to replace:

* `SCOPE` = `pg-cls2`
* `CONSUL_HOST` = `192.168.100.41:8500`
* `BACKUP_HOST` = `<BACKUP_HOST_IP>` (only if using remote repo)
* `PG_BIN_DIR` = path to PG binaries — on RHEL PGDG it's `/usr/pgsql-16/bin` (verify)

### Template (common parts)

Place each node file at `/etc/patroni/patroni.yml` with node-unique `name`, `restapi.connect_address`, `postgresql.connect_address`.

**Important**: `archive_command` uses pgBackRest `archive-push`. If using remote repo, ensure SSH/pgBackRest remote repo config is working.

---

### `/etc/patroni/patroni.yml` for pg-cls2-prod0 (192.168.100.47) — bootstrap node

```yaml
scope: pg-cls2
namespace: /service/
name: pg-cls2-prod0

consul:
  host: 192.168.100.41:8500
  register_service: true

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.100.47:8008

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - host replication replicator 0.0.0.0/0 md5
    - host all all 0.0.0.0/0 md5
  users:
    admin:
      password: "<ADMIN_PASSWORD>"
      options:
        - createrole
        - createdb

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.47:5432
  data_dir: /var/lib/postgresql/16/main
  bin_dir: /usr/pgsql-16/bin
  config_dir: /etc/postgresql/16/main
  pgpass: /var/lib/postgresql/.pgpass
  authentication:
    replication:
      username: replicator
      password: "<REPLICATOR_PASSWORD>"
    superuser:
      username: postgres
      password: "<POSTGRES_SUPERUSER_PASSWORD>"
  parameters:
    wal_level: replica
    max_wal_senders: 10
    max_replication_slots: 10
    wal_log_hints: 'on'
    hot_standby: 'on'
    archive_mode: 'on'
    archive_timeout: 60s
    # if using local repo:
    archive_command: 'pgbackrest --stanza=main archive-push %p'
    # If using remote repo, ensure pgbackrest is configured to push to remote repo.
```

### `/etc/patroni/patroni.yml` for pg-cls2-prod1 (192.168.100.48)

Change `name`, `restapi.connect_address`, `postgresql.connect_address`:

```yaml
name: pg-cls2-prod1
restapi:
  connect_address: 192.168.100.48:8008
postgresql:
  connect_address: 192.168.100.48:5432
# rest same as pg-cls2-prod0
```

### `/etc/patroni/patroni.yml` for pg-cls2-prod2 (192.168.100.49)

Change `name` and addresses accordingly.

**Permissions**:

```bash
chown postgres:postgres /etc/patroni/patroni.yml
chmod 600 /etc/patroni/patroni.yml
```

---

## 7 — systemd unit for Patroni (each node)

Create `/etc/systemd/system/patroni.service`:

```ini
[Unit]
Description=Patroni PostgreSQL cluster manager
After=network.target

[Service]
User=postgres
Group=postgres
Environment="PATH=/opt/patroni-venv/bin:/usr/bin:/bin"
ExecStart=/opt/patroni-venv/bin/patroni /etc/patroni/patroni.yml
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

Enable & reload systemd:

```bash
systemctl daemon-reload
systemctl enable patroni
```

---

## 8 — create .pgpass for replication (each node)

```bash
cat >/var/lib/postgresql/.pgpass <<EOF
192.168.100.47:5432:*:replicator:<REPLICATOR_PASSWORD>
192.168.100.48:5432:*:replicator:<REPLICATOR_PASSWORD>
192.168.100.49:5432:*:replicator:<REPLICATOR_PASSWORD>
EOF

chown postgres:postgres /var/lib/postgresql/.pgpass
chmod 600 /var/lib/postgresql/.pgpass
```

---

## 9 — start Patroni & bootstrap cluster (order matters)

1. Ensure Consul client is running on each node and server shows them alive.
2. **On pg-cls2-prod0 (bootstrap node)**: start Patroni

```bash
systemctl start patroni
journalctl -u patroni -f
```

* Patroni will `initdb` (if `data_dir` empty), create replication user, apply settings, register in Consul and become leader.

3. **On pg-cls2-prod1 & pg-cls2-prod2**: start Patroni

```bash
systemctl start patroni
```

They should clone from the primary and join as replicas.

4. Check cluster:

```bash
/opt/patroni-venv/bin/patronictl -c /etc/patroni/patroni.yml list
# or
patronictl -c /etc/patroni/patroni.yml list
```

You should see one `Leader` and two `Replica` nodes.

---

## 10 — pgBackRest stanza creation & test backup

### Quick local repo test (dev)

On **primary node** (as `postgres`):

```bash
mkdir -p /var/lib/pgbackrest
chown postgres:postgres /var/lib/pgbackrest

cat >/etc/pgbackrest/pgbackrest.conf <<'EOF'
[global]
repo1-path=/var/lib/pgbackrest
log-level-console=info

[main]
pg1-path=/var/lib/postgresql/16/main
EOF

chown postgres:postgres /etc/pgbackrest/pgbackrest.conf
sudo -u postgres pgbackrest --stanza=main stanza-create
sudo -u postgres pgbackrest --stanza=main --log-level-console=info backup
sudo -u postgres pgbackrest --stanza=main info
```

### Central repo (recommended)

* Configure backup host `/etc/pgbackrest/pgbackrest.conf` (repo1-path).
* On primary node configure pgbackrest to use remote repo (SSH-based remote repo config) or use a common NFS mount — follow pgBackRest docs for remote repo. (I can provide SSH remote repo config if you want.)

**Verify WAL archive**: check `pgbackrest --stanza=main info` and `pg_stat_archiver` on primary.

---

## 11 — Verify replication & archive

On primary:

```sql
SELECT pid, application_name, client_addr, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn
FROM pg_stat_replication;
```

On standby:

```sql
SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn(), now() - pg_last_xact_replay_timestamp() AS replay_delay;
```

Check WAL archive status on primary:

```sql
SELECT * FROM pg_stat_archiver;
```

---

## 12 — DNS failover via Consul + Patroni (service.master.\*)

Patroni registers services in Consul. If you want a stable DNS name for the primary:

* Patroni + Consul can register a **service name** like `pg-cls2-master` with tag `master`. Consul DNS returns the IP of the current master.
* Example DNS name: `master.pg-cls2.service.dc1.consul` (if you configure registration appropriately). You can use Consul DNS (port 8600) or configure `systemd-resolved` or `dnsmasq` to forward `*.consul` to `127.0.0.1:8600`.

**To use it**:

* Ensure Consul client on each node registers Patroni services (we set `register_service: true`).
* Query:

```bash
dig @127.0.0.1 -p 8600 A master.pg-cls2.service.dc1.consul
```

Applications can use that hostname to connect to primary without changing connection strings during failover.

---

## 13 — Test failover & recovery

### Controlled failover:

```bash
patronictl -c /etc/patroni/patroni.yml failover --candidate pg-cls2-prod1 --scheduled
# Or:
patronictl -c /etc/patroni/patroni.yml switchover pg-cls2-prod0 pg-cls2-prod1
```

### Kill the primary (simulate crash):

```bash
systemctl stop patroni   # or stop postgresql
# Patroni on remaining nodes should elect a new leader within a few seconds
patronictl -c /etc/patroni/patroni.yml list
```

### Rejoin old primary:

* Start Patroni on old primary. Patroni should use `pg_rewind` to resynchronize (if `use_pg_rewind: true` and `pg_rewind` available).

---

## 14 — Backups & PITR (pgBackRest)

* Schedule full backups (e.g., weekly) and incremental daily via cron on backup host or orchestrator.
* Example cron on backup host:

```
# as pgbackrest or root with appropriate environment
0 2 * * 0 pgbackrest --stanza=main --type=full backup
0 3 * * * pgbackrest --stanza=main --type=incr backup
```

* To restore: follow pgBackRest restore docs — typical workflow uses `pgbackrest --stanza=main restore` into an empty data dir, then start Postgres.

---

## 15 — Security & production hardening (must do before production)

* Use **strong passwords** and limit access to `.pgpass`.
* Use **TLS** for client-server connections (set `ssl` options) if required.
* Protect Consul with **ACLs** and TLS if production.
* Run Patroni with minimal privileges; keep config files permissioned to postgres (chmod 600).
* Store backups on an isolated backup host (no DB on backup host).
* Monitor disk usage for WAL archive to avoid disk full.
* Test pgBackRest restores and PITR regularly.

---

## 16 — Troubleshooting quick tips

* Patroni logs: `journalctl -u patroni -f`
* Postgres logs: `journalctl -u postgresql@16-main -f` (or PG log files)
* Consul client logs: `journalctl -u consul -f`
* If a node refuses to join: check `pg_rewind` availability and `pgbackrest` archive status.
* If WAL archive fails, check `archive_command` errors in Postgres logs.

---

## 17 — Example commands summary (copy/paste)

```bash
# Start patroni:
systemctl start patroni

# Check cluster:
patronictl -c /etc/patroni/patroni.yml list

# Check pg_stat_replication on primary:
psql -c "select application_name, client_addr, state from pg_stat_replication;"

# Create local pgbackrest stanza (on primary for quick test):
sudo -u postgres pgbackrest --stanza=main stanza-create
sudo -u postgres pgbackrest --stanza=main --log-level-console=info backup
sudo -u postgres pgbackrest --stanza=main info
```

---

## 18 — Next steps I can provide (pick any)

* Produce exact `patroni.yml` files for **all three nodes** already filled with your concrete IPs and binary paths and with placeholders for secrets.
* Provide `pgbackrest` **remote-repo (SSH)** example to store backups on a central backup server.
* Ansible playbook tasks to deploy Consul client + Patroni + pgBackRest across the nodes.
* A `systemd` + SELinux policy snippet if SELinux is enforced.

Tell me which one you want next and I’ll produce it ready-to-run (e.g., *“Give me the three patroni.yml files and the pgbackrest.conf for a central backup host”*).




Here’s your **PostgreSQL HADR (streaming replication) setup guide** with **Patroni**, **Consul**, and **pgBackRest**, formatted in **Markdown** for clarity and easy reading.

---

# PostgreSQL HADR Setup with Patroni, Consul, and pgBackRest

## **Cluster Topology**

| Node Name       | IP Address     | Role              |
| --------------- | -------------- | ----------------- |
| `pg-cls2-prod0` | 192.168.100.47 | Primary / Replica |
| `pg-cls2-prod1` | 192.168.100.48 | Replica           |
| `pg-cls2-prod2` | 192.168.100.49 | Replica           |

---

## **1. Install Required Packages on All Nodes**

```bash
# Install PostgreSQL 16
sudo apt update && sudo apt install -y postgresql-16 postgresql-client-16

# Install Patroni dependencies
sudo apt install -y python3-pip python3-psycopg2 python3-yaml python3-requests
pip install patroni[consul]

# Install Consul
sudo apt install -y unzip curl
CONSUL_VERSION=1.17.0
curl -OL https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip
unzip consul_${CONSUL_VERSION}_linux_amd64.zip
sudo mv consul /usr/local/bin/
sudo mkdir -p /etc/consul.d /var/lib/consul

# Install pgBackRest
sudo apt install -y pgbackrest
```

---

## **2. Configure Consul**

### **Server Node (Choose 1 or 3 nodes for Consul server)**

```bash
sudo tee /etc/consul.d/consul.hcl > /dev/null <<EOF
server = true
bootstrap_expect = 3
datacenter = dc1
data_dir = "/var/lib/consul"
bind_addr = "{{ NODE_IP }}"
advertise_addr = "{{ NODE_IP }}"
ui_config {
  enabled = true
}
client_addr = "0.0.0.0"
EOF
```

### **Client Nodes**

```bash
sudo tee /etc/consul.d/consul.hcl > /dev/null <<EOF
server = false
datacenter = dc1
data_dir = "/var/lib/consul"
bind_addr = "{{ NODE_IP }}"
advertise_addr = "{{ NODE_IP }}"
retry_join = ["192.168.100.47", "192.168.100.48", "192.168.100.49"]
EOF
```

Start Consul:

```bash
sudo systemctl enable consul --now
```

---

## **3. Configure pgBackRest**

Create repository on all nodes:

```bash
sudo mkdir -p /var/lib/pgbackrest
sudo chown postgres:postgres /var/lib/pgbackrest
```

Example config `/etc/pgbackrest/pgbackrest.conf`:

```ini
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2

[pgcluster]
pg1-path=/var/lib/postgresql/16/main
```

---

## **4. Configure Patroni**

### **Create Patroni Config File** `/etc/patroni/patroni.yml`

Example for `pg-cls2-prod0`:

```yaml
scope: pg-cls2
namespace: /service/
name: pg-cls2-prod0

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.100.47:8008

consul:
  host: 127.0.0.1:8500
  register_service: true

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.100.47:5432
  data_dir: /var/lib/postgresql/16/main
  bin_dir: /usr/lib/postgresql/16/bin
  authentication:
    replication:
      username: replicator
      password: repl_password
    superuser:
      username: postgres
      password: super_password
  parameters:
    wal_level: replica
    hot_standby: "on"
    max_wal_senders: 10
    max_replication_slots: 10

bootstrap:
  method: initdb
  dcs:
    postgresql:
      parameters:
        archive_mode: "on"
        archive_command: 'pgbackrest --stanza=pgcluster archive-push %p'
  initdb:
    - encoding: UTF8
    - data-checksums
```

Repeat for `pg-cls2-prod1` and `pg-cls2-prod2`, updating `name` and `connect_address`.

---

## **5. Start Patroni**

```bash
sudo systemctl enable patroni --now
```

---

## **6. Validate Setup**

* Check Patroni cluster status:

```bash
patronictl -c /etc/patroni/patroni.yml list
```

* Check Consul service registration:

```bash
consul catalog services
```

You should see:

```
master.pg-cls2.service.dc1
replica.pg-cls2.service.dc1
```

---

## **7. Test Failover**

```bash
patronictl -c /etc/patroni/patroni.yml failover
```

---

✅ **Result:**
You will be able to access the primary node using:

```
master.pg-cls2.service.dc1
```

and replicas via:

```
replica.pg-cls2.service.dc1
```

---

If you want, I can now **extend this guide with a detailed network diagram** showing how **Patroni, Consul, PostgreSQL, and pgBackRest interact** in your cluster. That will make it easier to visualize the setup.
