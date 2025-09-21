# [Postgres Exporter](https://grafana.com/oss/prometheus/exporters/postgres-exporter/?tab=installation)
[Blog post](https://schh.medium.com/monitoring-postgresql-databases-using-postgres-exporter-along-with-prometheus-and-grafana-1d68209ca687)

## *Step 1*: Setting up Postgres Exporter
```
# switch to postgres user
sudo su - postgres

# create scripts directory
mkdir /var/lib/postgresql/16/scripts

cd /var/lib/postgresql/16/scripts/

# download binary
wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.17.1/postgres_exporter-0.17.1.linux-amd64.tar.gz

# unzip tarball
tar xvfz postgres_exporter-*.linux-amd64.tar.gz

cd postgres_exporter-*.linux-amd64

# create a .pgpass file in postgres user home directory
cat >> ~/.pgpass <<EOF
*:*:*:postgres:YourStringSuperUserPasswordHere

# create environment variable for DATA_SOURCE_NAME
export DATA_SOURCE_NAME='postgresql://postgres@localhost:5432/postgres?sslmode=require'

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

create systemd service file.
```
sudo nano /etc/systemd/system/postgres_exporter.service
```

Add following content -
```
[Unit]
Description=PostgreSQL Exporter
Documentation=https://github.com/prometheus-community/postgres_exporter
After=network-online.target postgresql.service # Ensure network and PostgreSQL are up

[Service]
User=postgres
Group=postgres
WorkingDirectory=/var/lib/postgresql/16/scripts/postgres_exporter-0.17.1.linux-amd64
ExecStart=/var/lib/postgresql/16/scripts/postgres_exporter-0.17.1.linux-amd64/postgres_exporter
Restart=on-failure
StandardOutput=journal
StandardError=journal

# Environment variables for PostgreSQL connection (choose one method)
# Method 1: If using .pgpass, ensure the file is correctly configured for the postgres user
# Environment="PGHOST=localhost" "PGPORT=5432" "PGUSER=postgres" "PGDATABASE=postgres"

# Method 2: If you need to specify the DSN directly (less secure for password)
# Environment="DATA_SOURCE_NAME=postgresql://postgres:yourpostgresuserpassword@localhost:5432/postgres?sslmode=require"

# Method 3: If you removed the password from DSN and rely on .pgpass (recommended with .pgpass)
Environment="DATA_SOURCE_NAME=postgresql://postgres@localhost:5432/postgres?sslmode=require"


[Install]
WantedBy=multi-user.target
```

Reload systemd and Enable/Start the service
```
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
                └─1808804 /var/lib/postgresql/16/scripts/postgres_exporter-0.17.1.linux-amd64/postgres_exporter

    Jul 22 15:31:26 ryzen9 systemd[1]: Started postgres_exporter.service - PostgreSQL Exporter.
    Jul 22 15:31:26 ryzen9 postgres_exporter[1808804]: time=2025-07-22T10:01:26.653Z level=WARN source=main.go:85 msg="Error loading config" err="Error opening config file \"postgres_exporter.yml\": open postgres_export>
    Jul 22 15:31:26 ryzen9 postgres_exporter[1808804]: time=2025-07-22T10:01:26.653Z level=INFO source=main.go:95 msg="Excluded databases" databases=[]
    Jul 22 15:31:26 ryzen9 postgres_exporter[1808804]: time=2025-07-22T10:01:26.654Z level=INFO source=tls_config.go:347 msg="Listening on" address=[::]:9187
    Jul 22 15:31:26 ryzen9 postgres_exporter[1808804]: time=2025-07-22T10:01:26.654Z level=INFO source=tls_config.go:350 msg="TLS is disabled." http2=false address=[::]:9187
```

## *Step 2*: Scraping Postgres Exporter using Prometheus

Edit /etc/prometheus/prometheus.yml

```
- job_name: postgres
  static_configs:
  - targets: ['localhost:9187']
```