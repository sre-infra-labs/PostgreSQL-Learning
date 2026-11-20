# [Postgres Exporter](https://grafana.com/oss/prometheus/exporters/postgres-exporter/?tab=installation)
[Blog post](https://schh.medium.com/monitoring-postgresql-databases-using-postgres-exporter-along-with-prometheus-and-grafana-1d68209ca687)

## *Step 1*: Setting up Postgres Exporter

```bash
# switch to postgres user
sudo su - postgres

# create scripts directory
mkdir /var/lib/postgresql/18/scripts

cd /var/lib/postgresql/18/scripts/

# download binary
wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.21.1/postgres_exporter-0.21.1.linux-amd64.tar.gz

# unzip tarball
tar xvfz postgres_exporter-*.linux-amd64.tar.gz

cd postgres_exporter-*.linux-amd64
ln -s postgres_exporter-0.21.1.linux-amd64 postgres_exporter

# create a .pgpass file in postgres user home directory
cat <<'EOF' > ~/.pgpass
*:*:*:postgres:YourStringSuperUserPasswordHere
EOF

chmod 600 ~/.pgpass

# create environment file for DATA_SOURCE_NAME
cat <<'EOF' > /etc/postgresql/postgres_exporter.env
export DATA_SOURCE_NAME='postgresql://postgres@localhost:5432/postgres?sslmode=require'
EOF

    # NOT REQUIRED as pgpass file exists
    export DATA_SOURCE_NAME='postgresql://postgres:yourpostgresuserpassword@localhost:5432/postgres?sslmode=require'

# start exporter
./postgres_exporter

    time=2025-07-22T09:32:07.928Z level=WARN source=main.go:85 msg="Error loading config" err="Error opening config file \"postgres_exporter.yml\": open postgres_exporter.yml: no such file or directory"
    time=2025-07-22T09:32:07.928Z level=INFO source=main.go:95 msg="Excluded databases" databases=[]
    time=2025-07-22T09:32:07.929Z level=INFO source=tls_config.go:347 msg="Listening on" address=[::]:9187
    time=2025-07-22T09:32:07.929Z level=INFO source=tls_config.go:350 msg="TLS is disabled." http2=false address=[::]:9187
    time=2025-07-22T09:32:31.596Z level=INFO source=server.go:73 msg="Established new database connection" fingerprint=localhost:5432
    time=2025-07-22T09:32:31.602Z level=INFO source=postgres_exporter.go:615 msg="Semantic version changed" server=localhost:5432 from=0.0.0 to=16.9.0


# Test if things worked
curl http://localhost:9187/metrics

# add firewall exception if needed
sudo ufw allow 9187/tcp

```

## *Step 2: Create a systemd service


```bash
# Create a systemd service file
sudo tee /etc/systemd/system/postgres_exporter.service > /dev/null <<'EOF'
[Unit]
Description=PostgreSQL Exporter
Documentation=https://github.com/prometheus-community/postgres_exporter
After=network-online.target postgresql.service # Ensure network and PostgreSQL are up

[Service]
User=postgres
Group=postgres
EnvironmentFile=/etc/postgresql/postgres_exporter.env
WorkingDirectory=/var/lib/postgresql/18/scripts/postgres_exporter-0.21.1.linux-amd64
ExecStart=/var/lib/postgresql/18/scripts/postgres_exporter-0.21.1.linux-amd64/postgres_exporter \
  --collector.database_wraparound \
  --collector.stat_checkpointer \
  --collector.stat_activity_autovacuum \
  --collector.statio_user_indexes \
  --collector.long_running_transactions \
  --collector.stat_statements
Restart=on-failure
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF


# Reload systemd and Enable/Start the service
sudo systemctl daemon-reload
sudo systemctl enable postgres_exporter.service
sudo systemctl start postgres_exporter.service
sudo journalctl -u postgres_exporter.service -f

sudo systemctl status postgres_exporter.service

    |------------$ sudo systemctl status postgres_exporter.service 
    ● postgres_exporter.service - PostgreSQL Exporter
        Loaded: loaded (/etc/systemd/system/postgres_exporter.service; enabled; preset: enabled)
        Active: active (running) since Tue 2025-07-22 15:31:26 IST; 7s ago
        Docs: https://github.com/prometheus-community/postgres_exporter
    Main PID: 1808804 (postgres_export)
        Tasks: 5 (limit: 154376)
        Memory: 2.2M (peak: 2.8M)
            CPU: 4ms
        CGroup: /system.slice/postgres_exporter.service
                └─1808804 /var/lib/postgresql/18/scripts/postgres_exporter-0.21.1.linux-amd64/postgres_exporter

    Jul 22 15:31:26 ryzen9 systemd[1]: Started postgres_exporter.service - PostgreSQL Exporter.
    Jul 22 15:31:26 ryzen9 postgres_exporter[1808804]: time=2025-07-22T10:01:26.653Z level=WARN source=main.go:85 msg="Error loading config" err="Error opening config file \"postgres_exporter.yml\": open postgres_export>
    Jul 22 15:31:26 ryzen9 postgres_exporter[1808804]: time=2025-07-22T10:01:26.653Z level=INFO source=main.go:95 msg="Excluded databases" databases=[]
    Jul 22 15:31:26 ryzen9 postgres_exporter[1808804]: time=2025-07-22T10:01:26.654Z level=INFO source=tls_config.go:347 msg="Listening on" address=[::]:9187
    Jul 22 15:31:26 ryzen9 postgres_exporter[1808804]: time=2025-07-22T10:01:26.654Z level=INFO source=tls_config.go:350 msg="TLS is disabled." http2=false address=[::]:9187
```

## *Step 2*: Scraping Postgres Exporter using Prometheus

Edit /etc/prometheus/prometheus.yml

```
# job_name is "postgres" on official github website. So all dashboards use same.
- job_name: postgres
  static_configs:
  - targets: ['localhost:9187']
    labels:
      host: "ryzen9"
```

## *Step 3*: Enable additional collectors

The exporter enables the common collectors by default. The collectors below are off by default, and the dashboards need some of them. The flags are already in the `ExecStart` line of Step 2.

| Flag | Adds |
|---|---|
| `--collector.database_wraparound` | Transaction and multixact ID age per database (wraparound panels) |
| `--collector.stat_checkpointer` | Checkpoint counters on PostgreSQL 17+ (checkpoint panels) |
| `--collector.stat_activity_autovacuum` | Autovacuum worker activity |
| `--collector.statio_user_indexes` | Index I/O statistics |
| `--collector.long_running_transactions` | Transactions open longer than a threshold |
| `--collector.stat_statements` | Per-query statistics; needs `pg_stat_statements` in the database the exporter connects to |

Enabled by default (no flag needed): `database`, `locks`, `replication`, `replication_slots`, `settings`, `stat_activity`, `stat_archiver`, `stat_bgwriter`, `stat_database`, `stat_progress_vacuum`, `stat_replication`, `stat_user_tables`, `statio_user_tables`, `wal`.

Apply the change:

```bash
sudo systemctl daemon-reload
sudo systemctl restart postgres_exporter
```

Check that the new metrics appear:

```bash
curl -s http://localhost:9187/metrics | grep -E 'wraparound|checkpointer|autovacuum' | cut -c1-120 | head
```

Notes:
- `--auto-discover-databases` is needed to collect table-level statistics for databases other than the one in `DATA_SOURCE_NAME`. The exporter README marks it as deprecated, so check `postgres_exporter --help` on your version before using it.
- The `--extend.query-path` option for custom queries is also deprecated in the README. Prefer the built-in collectors above.
