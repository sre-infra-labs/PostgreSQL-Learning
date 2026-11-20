## 9. Backups with pgBackRest

For backup, we use `/vm-storage-02/pgbackrest/<pg-server-hostname>` as the repo path. This is a Samba shared directory.

### 9.1 Install

```bash
sudo apt update && sudo apt install -y pgbackrest      # Ubuntu/Debian
sudo dnf install -y pgbackrest                         # RHEL/Fedora
```

### 9.2 Create the repo directory on the Samba share

```bash
sudo mkdir -p /vm-storage-02/pgbackrest/$(hostname)
sudo chown -R postgres:postgres /vm-storage-02/pgbackrest/$(hostname)
sudo chmod 0750 /vm-storage-02/pgbackrest/$(hostname)
```

Samba mount notes are in `book--learn-postgres/chp19-useful-tools-n-extensions.md` (section "Samba Shared Directory for pgbackrest of remote PostgreSQL Servers").

### 9.3 Create `/etc/pgbackrest/pgbackrest.conf`

```ini
[global]
repo1-path=/vm-storage-02/pgbackrest/<pg-server-hostname>
repo1-retention-full=2
repo1-retention-diff=6
start-fast=y
log-level-console=info
log-level-file=detail
log-path=/var/log/pgbackrest
process-max=2

[main]
pg1-path=/var/lib/postgresql/<ver>/<cluster>
pg1-port=5432
pg1-user=postgres
```

```bash
sudo mkdir -p /var/log/pgbackrest
sudo chown postgres:postgres /var/log/pgbackrest
sudo mkdir -p /etc/pgbackrest
sudo nano /etc/pgbackrest/pgbackrest.conf
sudo chown postgres:postgres /etc/pgbackrest/pgbackrest.conf
sudo chmod 0640 /etc/pgbackrest/pgbackrest.conf
```

### 9.4 Enable WAL archiving in `conf.d/dba.conf`

```conf
wal_level = replica
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
archive_timeout = 60
```

Restart PostgreSQL (`archive_mode` needs a restart):

```bash
sudo systemctl restart postgresql
```

### 9.5 Create the stanza, check, and take the first backup

```bash
sudo -u postgres pgbackrest --stanza=main stanza-create
sudo -u postgres pgbackrest --stanza=main check
sudo -u postgres pgbackrest --stanza=main backup --type=full
sudo -u postgres pgbackrest info
```

Schedule backups with pg_cron ([section 6](06-pg-cron-jobs.md)) or cron:

```bash
# /etc/cron.d/pgbackrest
30 0 * * 0 postgres pgbackrest --stanza=main backup --type=full
30 0 * * 1-6 postgres pgbackrest --stanza=main backup --type=diff
```

Reference: `book--learn-postgres/chp19-useful-tools-n-extensions.md` (section "Disaster Recovery with pgbackrest") and `book--learn-postgres/chp15-backup-and-restore.md`.
