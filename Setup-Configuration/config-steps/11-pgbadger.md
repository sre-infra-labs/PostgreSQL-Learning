## 11. pgBadger setup - [PostgreSQL-Learning/Setup-Configuration/pgBadger-settings.md](../../Setup-Configuration/pgBadger-settings.md)

Goal: one pgBadger environment that imports new log lines incrementally from every PostgreSQL server about once a minute, keeps one report per server, and serves the reports on `http://localhost:8000`. Adding a server means adding one line to a config file.

Logs come from [section 3](03-logging.md). Remote servers need the passwordless SSH from [section 12](12-passwordless-ssh.md).

### 11.1 Install and create directories

```bash
sudo apt install -y pgbadger
sudo mkdir -p /var/lib/pgbadger/data/html
sudo chown -R postgres:www-data /var/lib/pgbadger/
sudo chmod -R 770 /var/lib/pgbadger/
sudo mkdir -p /etc/pgbadger
```

Each server gets its own folder under `/var/lib/pgbadger/data/html/<server>/`. pgbadger keeps its incremental state (`LAST_PARSED`) there, so each server's report is cumulative and servers never mix.

### 11.2 Server list

`/etc/pgbadger/servers.conf` has one server per line: a name, then the log source. A local path or glob reads local files. An `ssh://` URI reads remote files over SSH. Lines starting with `#` are ignored.

```bash
sudo tee /etc/pgbadger/servers.conf > /dev/null <<'EOF'
# name      log source
localhost   /var/log/postgresql/postgresql-*.log
sqlred      ssh://postgres@sqlred//var/log/postgresql/postgresql-*.log
sqlbuntu    ssh://postgres@sqlbuntu//var/log/postgresql/postgresql-*.log
EOF
sudo chown root:postgres /etc/pgbadger/servers.conf
sudo chmod 0640 /etc/pgbadger/servers.conf
```

Make unreachable servers fail fast. Without this, a down host can hang an import, and the lock then skips every later run. Add SSH defaults for the `postgres` user:

```bash
sudo -u postgres mkdir -p /var/lib/postgresql/.ssh
sudo -u postgres tee -a /var/lib/postgresql/.ssh/config > /dev/null <<'EOF'
Host sqlred sqlbuntu
  ConnectTimeout 5
  ServerAliveInterval 5
  ServerAliveCountMax 2
  BatchMode yes
EOF
sudo chmod 0600 /var/lib/postgresql/.ssh/config
```

`BatchMode yes` stops SSH from waiting for a password prompt. Add each new remote host to the `Host` line.

### 11.3 Import script

`/usr/local/bin/pgbadger-import` does two things:

1. For each server, runs `pgbadger -I`. This reads only the log lines added since the last run and updates that server's report.
2. Regenerates the home page `index.html`, which links to each server's report.

Safety:
- A lock file (`flock`) makes sure a run doesn't start while the previous one is still going. If it is, the new run exits quietly.
- If one server fails, the others still run, and the script exits non-zero so systemd records the failure.

```bash
sudo tee /usr/local/bin/pgbadger-import > /dev/null <<'EOF'
#!/usr/bin/env bash
# Incremental pgBadger import for every server in servers.conf, then refresh the home page.
set -uo pipefail
CONF=/etc/pgbadger/servers.conf
BASE=/var/lib/pgbadger/data/html
status=0

# Do not overlap with a run that is still going
exec 9>/var/lib/pgbadger/import.lock
flock -n 9 || { echo "previous import still running, skipping" >&2; exit 0; }

while read -r name source; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue
  mkdir -p "$BASE/$name"
  # A failure in one server only affects that server: record it and move on.
  # Remote sources get a time limit so a down host cannot hold the lock.
  limit=()
  [[ "$source" == ssh://* ]] && limit=(timeout 50)
  # $source is intentionally unquoted so local globs expand.
  # -I parses only new lines, using LAST_PARSED in the output folder.
  if "${limit[@]}" pgbadger -q -I --outdir "$BASE/$name" $source 2> "$BASE/$name/last_error.txt"; then
    date '+%F %T' > "$BASE/$name/last_ok.txt"
    rm -f "$BASE/$name/last_error.txt"
  else
    echo "pgbadger import failed for $name (see $BASE/$name/last_error.txt)" >&2
    status=1
  fi
done < "$CONF"

# Home page: one line per server, showing whether its last import worked
{
  echo '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>pgBadger reports</title></head><body style="font-family:sans-serif;margin:16px">'
  echo "<h1>pgBadger reports</h1><p>Updated $(date '+%F %T')</p><ul>"
  for dir in "$BASE"/*/; do
    [[ -d "$dir" ]] || continue
    name=$(basename "$dir")
    last_ok=$(cat "$dir/last_ok.txt" 2>/dev/null || echo "never")
    if [[ -f "$dir/last_error.txt" ]]; then
      state="DOWN, last OK: $last_ok"
    else
      state="OK, last import: $last_ok"
    fi
    echo "<li><a href=\"$name/index.html\">$name</a> - $state</li>"
  done
  echo '</ul></body></html>'
} > "$BASE/index.html.tmp" && mv "$BASE/index.html.tmp" "$BASE/index.html"

exit $status
EOF
sudo chmod 0755 /usr/local/bin/pgbadger-import
```

### 11.4 Schedule the import every minute with a systemd timer

The timer runs the script every minute. `AccuracySec=5s` matters: systemd's default accuracy is one minute, which would let runs slip and push the delay past one minute.

```bash
sudo tee /etc/systemd/system/pgbadger-import.service > /dev/null <<'EOF'
[Unit]
Description=Incremental pgBadger import for all PostgreSQL servers
After=network-online.target

[Service]
Type=oneshot
User=postgres
Group=postgres
ExecStart=/usr/local/bin/pgbadger-import
EOF

sudo tee /etc/systemd/system/pgbadger-import.timer > /dev/null <<'EOF'
[Unit]
Description=Run incremental pgBadger import every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=5s
Persistent=true
Unit=pgbadger-import.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now pgbadger-import.timer
```

Worst-case delay: a log line is written, then picked up by the next run, which starts within about a minute, plus the parse time. Remote servers add the SSH round trip.

### 11.5 Serve the reports on localhost:8000 with Docker

The report site runs in a container. The reports folder on the host is bind-mounted read-only at `/reports`, so the container always shows the latest files written by the import timer. Nothing is copied into the container, and the reports stay on the host.

The container runs as the `postgres` user's UID and the `www-data` group's GID. That lets it read the reports, which are in a folder that is only readable by those two, without loosening the permissions from 11.1. It listens on `127.0.0.1` only.

Install Docker if it's not present (Ubuntu):

```bash
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
```

Create the compose project:

```bash
sudo mkdir -p /opt/pgbadger-report
sudo tee /opt/pgbadger-report/docker-compose.yml > /dev/null <<'EOF'
services:
  pgbadger-report:
    image: python:3.12-alpine
    container_name: pgbadger-report
    restart: unless-stopped
    user: "${PG_UID}:${WWW_GID}"
    command: python -m http.server 8000 --directory /reports
    ports:
      - "127.0.0.1:8000:8000"
    volumes:
      - /var/lib/pgbadger/data/html:/reports:ro
EOF

sudo tee /opt/pgbadger-report/.env > /dev/null <<EOF
PG_UID=$(id -u postgres)
WWW_GID=$(getent group www-data | cut -d: -f3)
EOF
sudo chmod 0644 /opt/pgbadger-report/.env
```

Start it:

```bash
cd /opt/pgbadger-report
sudo docker compose up -d
sudo docker compose ps
```

Open `http://localhost:8000/` in a browser. The home page links to each server's report.

Notes:
- `restart: unless-stopped` brings the container back after a reboot, as long as the Docker service is enabled.
- The container is read-only for the reports. Only the import script on the host writes to them.
- To stop serving, run `sudo docker compose down` in `/opt/pgbadger-report`.
- If the page shows 403 errors, check that the `.env` UIDs match `id -u postgres` and `getent group www-data`.

### 11.6 Verify

Run one import now, without waiting for the timer:

```bash
sudo systemctl start pgbadger-import.service
sudo journalctl -u pgbadger-import.service -n 50 --no-pager
systemctl list-timers pgbadger-import.timer --no-pager
ls /var/lib/pgbadger/data/html/localhost/
curl -s http://localhost:8000/ | head -20
```

To confirm the delay, write a test line to the log and watch for it in the report within a minute or two:

```bash
sudo -u postgres psql -c "SELECT 'pgbadger delay test $(date +%T)';" > /dev/null
```

Check the remote SSH access that the `sqlred` and `sqlbuntu` lines need:

```bash
sudo -u postgres ssh postgres@sqlred 'ls /var/log/postgresql | tail -3'
sudo -u postgres ssh postgres@sqlbuntu 'ls /var/log/postgresql | tail -3'
```

### 11.7 Add a server later

1. Confirm passwordless SSH works (section 11.6, or section 12 for a new host).
2. Add one line to `/etc/pgbadger/servers.conf`.
3. Run `sudo systemctl start pgbadger-import.service` to import it now. The timer picks it up on the next run anyway.

### Notes

- Incremental state is per server. If you delete a server's folder, its next import starts from the beginning of its logs.
- Each run re-renders the whole HTML report for each server, so the work per run grows with the total log history. If runs start taking longer than a minute, the lock file will skip runs. Check the journal for "previous import still running". Options are a longer interval or a smaller log window.
- Remote servers are read over SSH every minute. Keep the number of remote servers small, or use a longer interval for them.
- Log cleanup from [section 3](03-logging.md) compresses logs older than 7 days, and the `postgresql-*.log` glob above does not match the `.gz` files. Check `journalctl -u pgbadger-import` after the first week to confirm nothing breaks.
- Day-by-day reports are not built in this setup. Use pgBadger's own date navigation inside each server's report.
