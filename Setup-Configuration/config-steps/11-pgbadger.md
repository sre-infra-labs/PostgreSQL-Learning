## 11. pgBadger setup - [PostgreSQL-Learning/Setup-Configuration/pgBadger-settings.md](../../Setup-Configuration/pgBadger-settings.md)

Goal: one pgBadger environment that imports new log lines incrementally from every PostgreSQL server about once a minute, keeps one report per server, and serves the reports on `http://localhost:8000`. Adding a server means adding one line to a config file.

Logs come from [section 3](03-logging.md). Remote servers need the passwordless SSH from [section 12](12-passwordless-ssh.md).

### 11.1 Install and create directories

```bash
sudo apt install -y pgbadger
sudo mkdir -p /var/lib/pgbadger/data/html
sudo mkdir -p /etc/pgbadger

# The import service runs as saanvi. It writes the reports (group www-data)
# and reads the local postgres logs (group postgres).
# Group changes apply to new login sessions only: log out and back in before testing by hand.
sudo usermod -aG www-data,postgres saanvi
sudo chown -R saanvi:www-data /var/lib/pgbadger
sudo chmod -R g+rwX /var/lib/pgbadger
# setgid on folders: files created later inherit the www-data group
sudo find /var/lib/pgbadger -type d -exec chmod g+s {} +
```

Each server gets its own folder under `/var/lib/pgbadger/data/html/<server>/`. pgbadger keeps its incremental state (`LAST_PARSED`) there, so each server's report is cumulative and servers never mix.


### 11.2 Permissions on Remote machines for postgresql log reading

```bash
# ssh remote machine
ssh sqlred

# add remote user used for ssh to postgres group
sudo usermod -aG postgres $USER

# 1. Let the postgres group traverse the parent (group only, not other)
sudo chmod g+x /var/lib/postgresql

# 2. Give the log directory group read+execute, and undo the earlier -R o+x
sudo chown postgres:postgres /var/lib/postgresql/log
sudo chmod 750 /var/lib/postgresql/log

# 3. Make existing log files group-readable, and remove the stray other-execute bit
sudo find /var/lib/postgresql/log -type f -exec chmod 640 {} +

# 4. Refresh the terminal permissions
newgrp postgres

# 5. Change timezone to IST
sudo timedatectl set-timezone Asia/Kolkata
timedatectl | grep 'Time zone'
date

# 6. Test from the local machine, after logging out and back in
ssh sqlred 'ls -l /var/lib/postgresql/log/ | tail -3'
```


### 11.3 Server list

`/etc/pgbadger/servers.conf` has one server per line: a name, then the log source. A local path or glob reads local files. An `ssh://` URI reads remote files over SSH. Lines starting with `#` are ignored.

```bash
sudo tee /etc/pgbadger/servers.conf > /dev/null <<'EOF'
# name      log source
localhost   /var/log/postgresql/postgresql-20*.log
sqlred      ssh://sqlred//var/lib/postgresql/log/postgresql-20*.log
sqlbuntu    ssh://sqlbuntu//var/log/postgresql/postgresql-20*.log
EOF
sudo chown root:postgres /etc/pgbadger/servers.conf
sudo chmod 0640 /etc/pgbadger/servers.conf
```

Make unreachable servers fail fast. Without this, a down host can hang an import, and the lock then skips every later run. Add SSH defaults for the `saanvi` user (run as `saanvi`, not root):

```bash
mkdir -p ~/.ssh
# Append only if the block is not already there, so re-running this section does not duplicate it
grep -q '^Host sqlred sqlbuntu$' ~/.ssh/config 2>/dev/null || tee -a ~/.ssh/config > /dev/null <<'EOF'
Host sqlred sqlbuntu
  ConnectTimeout 5
  ServerAliveInterval 5
  ServerAliveCountMax 2
  BatchMode yes
EOF
chmod 0600 ~/.ssh/config
```

`BatchMode yes` stops SSH from waiting for a password prompt. Add each new remote host to the `Host` line.

The glob is `postgresql-20*.log` so that it matches only the timestamped files from [section 3](03-logging.md). Debian's `postgresql-18-main.log` and its rotated copies also sit in `/var/log/postgresql`, and a broader `postgresql-*.log` would import them too.

Check the `sqlbuntu` log path before the first import. `/var/log/postgresql` is an assumption; set it to wherever that server actually writes its logs.

The service runs as `saanvi`, so the remote hosts must accept `saanvi`'s SSH key, not the `postgres` user's.

### 11.4 Import script

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
  # 600 s covers the first full parse of a large remote history; lower it once the first import has finished
  [[ "$source" == ssh://* ]] && limit=(timeout 600)
  # $source is intentionally unquoted so local globs expand.
  # -I parses only new lines, using LAST_PARSED in the output folder.
  # -f stderr skips format detection, which fails for ssh:// sources.
  # </dev/null stops ssh inside pgbadger from reading the rest of servers.conf from stdin,
  # which would silently skip every server listed after this one.
  if "${limit[@]}" pgbadger -q -I -f stderr --outdir "$BASE/$name" $source 2> "$BASE/$name/last_error.txt" < /dev/null; then
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

### 11.5 Schedule the import every minute with a systemd timer

The timer runs the script every minute. `AccuracySec=5s` matters: systemd's default accuracy is one minute, which would let runs slip and push the delay past one minute.

```bash
# If the units already exist, stop the timer before replacing them (ignore the error on a first run)
sudo systemctl disable --now pgbadger-import.timer 2>/dev/null || true

sudo tee /etc/systemd/system/pgbadger-import.service > /dev/null <<'EOF'
[Unit]
Description=Incremental pgBadger import for all PostgreSQL servers
After=network-online.target

[Service]
Type=oneshot
User=saanvi
Group=www-data
# Files the import creates are group-writable, so www-data members can still read and write them
UMask=0002
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

### 11.6 Serve the reports on localhost:8000 with Docker

The report site runs in a container. The reports folder on the host is bind-mounted read-only at `/reports`, so the container always shows the latest files written by the import timer. Nothing is copied into the container, and the reports stay on the host.

The container runs as the `postgres` user's UID and the `www-data` group's GID. The reports folder is owned by `saanvi:www-data` with group read access (set in 11.1), so the container reads them through the `www-data` group. It listens on `127.0.0.1` only.

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

### 11.7 Verify

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
ssh sqlred 'ls /var/lib/postgresql/log | tail -3'
ssh sqlbuntu 'ls /var/log/postgresql | tail -3'
```

### 11.8 Add a server later

1. Confirm passwordless SSH works (section 11.7, or section 12 for a new host).
2. Add one line to `/etc/pgbadger/servers.conf`.
3. Run `sudo systemctl start pgbadger-import.service` to import it now. The timer picks it up on the next run anyway.

### 11.9 Troubleshooting

Start with the service journal and the per-server error file. The page shows DOWN whenever `last_error.txt` exists for a server.

```bash
journalctl -u pgbadger-import.service -n 30 --no-pager
sg www-data -c 'cat /var/lib/pgbadger/data/html/<server>/last_error.txt'
```

`sg www-data` lets you read the error files from a shell that doesn't have the group yet.

| Symptom in `last_error.txt` or journal | Cause | Fix |
|---|---|---|
| `Permission denied` on `/var/log/postgresql/...` (localhost) | `saanvi` can't read the local logs | Check `id -nG` includes `postgres`, and log out and back in if it doesn't. Check `ls -l /var/log/postgresql` shows group read. |
| Local logs are `-rw-------` (mode `0600`) | `log_file_mode` isn't applied | Set `log_file_mode = '0640'` in `conf.d/dba.conf`, run `SELECT pg_reload_conf();`, and `sudo chmod 0640 /var/log/postgresql/*.log` for existing files. |
| `Permission denied` writing `LAST_PARSED` or reports | Files under `/var/lib/pgbadger` still owned by `postgres` | `sudo chown -R saanvi:www-data /var/lib/pgbadger`, `sudo chmod -R g+rwX /var/lib/pgbadger`, `sudo find /var/lib/pgbadger -type d -exec chmod g+s {} +` |
| `another process is already started or remove the file, see /tmp/pgbadger.pid` | A manual pgBadger run is holding the default pid file | Wait for the other run to finish, or delete a stale `/tmp/pgbadger.pid`. For manual tests, add `--pid-dir /tmp/pgbadger-test` so they don't collide with the timer. |
| `Host key verification failed` | `saanvi` hasn't trusted that server's host key | Check the fingerprint, then run `ssh -o StrictHostKeyChecking=accept-new <host> true` as `saanvi`. |
| `No route to host` | Server is powered off or not reachable | `ping <host>`, and check the machine and network. |
| `unable to detect log file format ... please use -f option` | Format detection fails on `ssh://` sources | Use `-f stderr` in the script (section 11.4). |
| `Received SIGTERM abort parsing` | Remote parse ran past `timeout` | Raise `timeout` in the script (section 11.4). Lower it once the first import is done. |
| A server's `last_error.txt` and `last_ok.txt` are never updated, and the journal is silent | The loop stopped before reaching that server. A command inside the loop read stdin and consumed the rest of `servers.conf`. Servers after the first working remote one are then skipped. | Use `< /dev/null` on the `pgbadger` line in the script (section 11.4). |
| `FATAL: another process is already started` when running pgBadger by hand | The timer's run is holding `/tmp/pgbadger.pid` | Wait for `systemctl is-active pgbadger-import.service` to print `inactive`, then retry. Use `--pid-dir` for manual tests. |
| `previous import still running, skipping` in journal | A run takes longer than the interval, so the lock is held | Check run time. Raise the interval, or reduce the log window. |
| Service fails with `control process exited` but a server is OK | The script exits non-zero if any server fails | Look at the failing server's `last_error.txt`. This is expected behavior, not a separate bug. |
| Unit edits have no effect | systemd hasn't reloaded | `sudo systemctl daemon-reload`, then `sudo systemctl restart pgbadger-import.timer`. |
| Docker page shows 403 | `.env` UIDs don't match | Check `id -u postgres` and `getent group www-data` against `/opt/pgbadger-report/.env`. |

### Notes

- Incremental state is per server. If you delete a server's folder, its next import starts from the beginning of its logs.
- Each run re-renders the whole HTML report for each server, so the work per run grows with the total log history. If runs start taking longer than a minute, the lock file will skip runs. Check the journal for "previous import still running". Options are a longer interval or a smaller log window.
- Remote servers are read over SSH every minute. Keep the number of remote servers small, or use a longer interval for them.
- Log cleanup from [section 3](03-logging.md) compresses logs older than 7 days, and the `postgresql-*.log` glob above does not match the `.gz` files. Check `journalctl -u pgbadger-import` after the first week to confirm nothing breaks.
- Day-by-day reports are not built in this setup. Use pgBadger's own date navigation inside each server's report.
