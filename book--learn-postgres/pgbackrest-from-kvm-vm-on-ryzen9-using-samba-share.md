# pgBackRest on a Samba Share: KVM Host (ryzen9) + PostgreSQL 18 VM (sqlred)

End-to-end setup for storing pgBackRest backups from PostgreSQL VMs on a Samba share exported by the KVM hypervisor host.

## Contents

1. [Architecture and assumptions](#1-architecture-and-assumptions)
2. [Host setup (ryzen9)](#2-host-setup-ryzen9)
3. [VM setup (sqlred)](#3-vm-setup-sqlred)
4. [Scheduling backups](#4-scheduling-backups)
5. [Restore test](#5-restore-test)
6. [Adding more VMs](#6-adding-more-vms)
7. [Monitoring](#7-monitoring)
8. [Troubleshooting](#8-troubleshooting)
9. [Final checklist](#9-final-checklist)

---

## 1. Architecture and assumptions

```text
 sqlred VM (PostgreSQL 18)                       ryzen9 (KVM host, Ubuntu)
 ┌──────────────────────────┐   SMB 3 / TCP 445  ┌─────────────────────────────────────────┐
 │ postgres + pgbackrest    │ ─────────────────► │ smbd -> /stale-storage/share-stalestorage │
 │ /mnt/pgbackrest-repo     │                    │          /pgbackrest_backups              │
 └──────────────────────────┘                    └─────────────────────────────────────────┘
```

| Item                             | Value used in this guide                               |
| -------------------------------- | ------------------------------------------------------ |
| Host name / IP on the VM network | `ryzen9` / `192.168.100.1`                             |
| VM subnet                        | `192.168.100.0/24`                                     |
| Host directory (repo)            | `/stale-storage/share-stalestorage/pgbackrest_backups` |
| Samba share name                 | `pgbackrest`                                           |
| Samba / owner account on host    | `pgbackrest` (dedicated, no login shell)               |
| VM mount point                   | `/mnt/pgbackrest-repo`                                 |
| PostgreSQL                       | 18, data dir `/var/lib/postgresql/18/main`             |
| Stanza                           | `sqlred`                                               |

Design choices:

- **No guest access.** A dedicated Samba user owns everything. This avoids the `nobody`/ACL-mask permission problems that guest or usershare setups produce.
- **Explicit share in `smb.conf`** (not a `net usershare`), so masks and access rules actually apply.
- **Share root = the repo directory.** The VM's `repo1-path` is therefore the mount point itself.
- **Async archiving** so a slow or unreachable share does not stall PostgreSQL commits.

> Note: for Linux-to-Linux, NFS or virtiofs is simpler and avoids SMB semantics. This guide uses Samba as requested, and it works well with the settings below.

---

## 2. Host setup (ryzen9)

### 2.1 Install packages

```bash
sudo apt update
sudo apt install -y samba acl
```

### 2.2 Create a dedicated owner account

```bash
sudo groupadd --system pgbackrest
sudo useradd --system -g pgbackrest -M -s /usr/sbin/nologin pgbackrest

# Samba password (the VMs will use this)
sudo smbpasswd -a pgbackrest
```

### 2.3 Prepare the directory

This also takes ownership of any existing repo data (for example `sqlred` and `sqlbuntu`) and removes stale POSIX ACLs (the `+` in `ls -l`).

```bash
D=/stale-storage/share-stalestorage/pgbackrest_backups

sudo mkdir -p "$D"
sudo setfacl -R -b "$D"
sudo chown -R pgbackrest:pgbackrest "$D"
sudo find "$D" -type d -exec chmod 750 {} +
sudo find "$D" -type f -exec chmod 640 {} +
ls -ld "$D"
```

### 2.4 Remove the old share and clean `smb.conf`

If the old share was created as a usershare, delete it so it cannot shadow the new definition.

```bash
net usershare list
sudo net usershare delete share-stalestorage

sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.$(date +%F)
sudo nano /etc/samba/smb.conf
```

In that file:

- Remove any `force user`, `create mask` or `directory mask` lines you added under `[print$]`. Restore the stock values, or delete the section if you do not use printing.
- Do not keep a second `[global]` section.

### 2.5 Define the share

First find the host's address on the VM network (it should be `192.168.100.1`):

```bash
ip -br a
```

Add or merge these settings into `/etc/samba/smb.conf`. The `interfaces`, `bind interfaces only`, `server min protocol` and `map to guest` lines belong in your existing `[global]` section.

```ini
[global]
   interfaces = 127.0.0.1 192.168.100.1/24
   bind interfaces only = yes
   server min protocol = SMB3
   map to guest = never

[pgbackrest]
   path = /stale-storage/share-stalestorage/pgbackrest_backups
   comment = pgBackRest repository
   browseable = no
   read only = no
   guest ok = no
   valid users = pgbackrest
   hosts allow = 192.168.100.0/24 127.0.0.1
   create mask = 0640
   directory mask = 0750
```

Validate and restart:

```bash
sudo testparm -s | sed -n '/\[pgbackrest\]/,/^$/p'
sudo systemctl enable --now smbd
sudo systemctl restart smbd
sudo systemctl disable --now nmbd 2>/dev/null || true   # NetBIOS name service is not needed
```

### 2.6 Firewall

Only needed if `ufw` is active.

```bash
sudo ufw allow from 192.168.100.0/24 to any port 445 proto tcp
sudo ufw status
```

### 2.7 Test from the host

```bash
sudo apt install -y smbclient
smbclient //127.0.0.1/pgbackrest -U pgbackrest -c 'mkdir _t; rmdir _t; ls'
```

---

## 3. VM setup (sqlred)

### 3.1 Install packages

```bash
sudo apt update
sudo apt install -y cifs-utils pgbackrest
pgbackrest version
```

### 3.2 Store the credentials

```bash
sudo install -m 600 /dev/null /etc/pgbackrest-smb.cred
printf 'username=pgbackrest\npassword=CHANGE_ME\n' | sudo tee /etc/pgbackrest-smb.cred > /dev/null
sudo chmod 600 /etc/pgbackrest-smb.cred
```

Edit the file afterwards and replace `CHANGE_ME` with the real `smbpasswd` password.

### 3.3 Mount the share

Unmount any old mount and remove its `/etc/fstab` entry first.

```bash
sudo umount /mnt/pgbackrest-repo 2>/dev/null || true
sudo mkdir -p /mnt/pgbackrest-repo
```

Add this line to `/etc/fstab`:

```text
//192.168.100.1/pgbackrest  /mnt/pgbackrest-repo  cifs  credentials=/etc/pgbackrest-smb.cred,vers=3.1.1,uid=postgres,gid=postgres,file_mode=0640,dir_mode=0750,nobrl,soft,nofail,_netdev,x-systemd.automount  0  0
```

Mount and test as the `postgres` user:

```bash
sudo systemctl daemon-reload
sudo mount -a
mount | grep pgbackrest-repo

sudo -u postgres sh -c 'mkdir /mnt/pgbackrest-repo/_t && touch /mnt/pgbackrest-repo/_t/f && rm -r /mnt/pgbackrest-repo/_t && echo WRITE-OK'
```

Do not continue until you see `WRITE-OK`. A `touch` that reports "setting times ... Permission denied" is a CIFS quirk and does not affect pgBackRest, but mkdir and file creation must work.

### 3.4 Make PostgreSQL start after the mount (optional)

```bash
sudo systemctl edit postgresql@18-main
```

Add:

```ini
[Unit]
After=remote-fs.target
Wants=remote-fs.target
```

### 3.5 Configure pgBackRest

Edit `/etc/pgbackrest/pgbackrest.conf`:

```ini
[global]
repo1-path=/mnt/pgbackrest-repo
repo1-retention-full=2
repo1-retention-diff=7
compress-type=zst
process-max=2
start-fast=y
log-path=/var/log/pgbackrest
archive-async=y
spool-path=/var/spool/pgbackrest

[sqlred]
pg1-path=/var/lib/postgresql/18/main
```

Create the directories and fix permissions:

```bash
sudo install -d -o postgres -g postgres -m 750 /var/log/pgbackrest /var/spool/pgbackrest
sudo chown postgres:postgres /etc/pgbackrest/pgbackrest.conf
sudo chmod 640 /etc/pgbackrest/pgbackrest.conf
```

If you previously used `/mnt/pgbackrest-repo/pgbackrest_backups` as `repo1-path`, change it to `/mnt/pgbackrest-repo` on every VM, because the share root is now the repo directory.

### 3.6 Configure PostgreSQL archiving

```sql
ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=sqlred archive-push %p';
ALTER SYSTEM SET wal_level = 'replica';
```

Run it with:

```bash
sudo -u postgres psql
```

`archive_mode` requires a restart:

```bash
sudo systemctl restart postgresql@18-main
```

Confirm:

```sql
SHOW archive_mode;
SHOW archive_command;
SELECT pg_is_in_recovery();   -- must be f on the primary
```

### 3.7 Create the stanza, check, and take the first backup

For a new, empty repo:

```bash
sudo -u postgres pgbackrest --stanza=sqlred stanza-create
sudo -u postgres pgbackrest --stanza=sqlred check
sudo -u postgres pgbackrest --stanza=sqlred --type=full backup
sudo -u postgres pgbackrest --stanza=sqlred info
```

If the repo already contains a `sqlred` stanza from a previous cluster, compare system IDs before doing anything destructive:

```bash
sudo -u postgres /usr/lib/postgresql/18/bin/pg_controldata /var/lib/postgresql/18/main | grep -i 'system identifier'
sudo -u postgres pgbackrest --stanza=sqlred info
```

- **System IDs match:** just run `check`.
- **They differ and you still need the old backups:** run `stanza-upgrade`, or use a new stanza name for this cluster.
- **They differ and the old backups are disposable:** `stop`, `stanza-delete --force`, then `stanza-create` (this removes that stanza's backups from the repo).

```bash
sudo -u postgres pgbackrest --stanza=sqlred stanza-upgrade
```

```bash
sudo -u postgres pgbackrest --stanza=sqlred stop
sudo -u postgres pgbackrest --stanza=sqlred stanza-delete --force
sudo -u postgres pgbackrest --stanza=sqlred stanza-create
```

### 3.8 Verify archiving is healthy

```sql
SELECT archived_count, last_archived_wal, last_archived_time,
       failed_count, last_failed_wal, last_failed_time
FROM pg_stat_archiver;
```

`archived_count` should rise and `last_failed_time` should stay frozen.

---

## 4. Scheduling backups

Open the postgres user's crontab:

```bash
sudo -u postgres crontab -e
```

Add (times are local time on the VM):

```cron
30 1 * * 0    pgbackrest --stanza=sqlred --type=full backup
30 1 * * 1-6  pgbackrest --stanza=sqlred --type=diff backup
0  6 * * *    pgbackrest --stanza=sqlred check
```

---

## 5. Restore test

Do this on a scratch VM, or at least in a maintenance window. A backup that has never been restored is unproven.

Restore the latest state:

```bash
sudo systemctl stop postgresql@18-main
sudo -u postgres pgbackrest --stanza=sqlred --delta restore
sudo systemctl start postgresql@18-main
```

Point-in-time restore:

```bash
sudo systemctl stop postgresql@18-main
sudo -u postgres pgbackrest --stanza=sqlred --delta --type=time \
  --target="2026-11-01 16:00:00+05:30" --target-action=promote restore
sudo systemctl start postgresql@18-main
```

Notes:

- Do not pass `--type=standby` unless you intend to build a replica. It creates `standby.signal`, which leaves the server read-only in recovery until promoted or until `primary_conninfo` is set.
- After a restore, `SELECT pg_is_in_recovery();` must return `f` before applications write.
- Run `verify` regularly:

```bash
sudo -u postgres pgbackrest --stanza=sqlred verify
```

---

## 6. Adding more VMs

Repeat Part 3 on each VM, with its own stanza name and `pg1-path`. The Samba share and credentials can be shared, or give each VM its own Samba user and subdirectory if you want isolation.

Example `/etc/pgbackrest/pgbackrest.conf` for another VM:

```ini
[global]
repo1-path=/mnt/pgbackrest-repo
repo1-retention-full=2
repo1-retention-diff=7
compress-type=zst
start-fast=y
log-path=/var/log/pgbackrest
archive-async=y
spool-path=/var/spool/pgbackrest

[sqlbuntu]
pg1-path=/var/lib/postgresql/16/main
```

Each VM then sets `archive_command = 'pgbackrest --stanza=<its-stanza> archive-push %p'`.

---

## 7. Monitoring

Useful checks to alert on:

```sql
-- archiving failures (alert when failed_count increases or last_archived_time is old)
SELECT archived_count, failed_count, last_archived_time, last_failed_time
FROM pg_stat_archiver;
```

```bash
# JSON output for scripts and exporters
sudo -u postgres pgbackrest --stanza=sqlred info --output=json
```

- Alert on "time since last successful backup" and on `failed_count` growth.
- If you use Prometheus, `pgbackrest_exporter` exposes backup age and archive status.
- Monitor free space on the host:

```bash
df -h /stale-storage
```

**Off-host copy:** the repo lives on the same hypervisor as the VMs, so a host failure loses both. Replicate the directory elsewhere, or add a second repo (`repo2-*` options, for example S3 or Azure Blob) in `pgbackrest.conf`.

---

## 8. Troubleshooting

| Symptom                                                      | Likely cause                                                           | Fix                                                                                                                                |
| ------------------------------------------------------------ | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `Permission denied` creating a directory in the repo         | Host files not owned by `pgbackrest`, stale ACLs, or wrong credentials | On the host run `sudo setfacl -R -b $D && sudo chown -R pgbackrest:pgbackrest $D`; verify the VM credentials file                  |
| `ArchiveMismatchError ... unable to find a valid repository` | Repo stanza belongs to a different cluster system ID                   | Compare `pg_controldata` with `pgbackrest info`; use `stanza-upgrade` or a new stanza                                              |
| `check` times out waiting for a WAL segment                  | `archive_command` failing                                              | `SELECT * FROM pg_stat_archiver;` then run `pgbackrest --stanza=sqlred --log-level-console=detail archive-push <wal file>` by hand |
| `pg_is_in_recovery()` is `t` unexpectedly                    | Leftover `standby.signal`/`recovery.signal`, no `primary_conninfo`     | Remove the signal file and restart, or run `SELECT pg_promote();` once you are sure no other primary exists                        |
| Hangs or `Stale file handle` after the host reboots          | Dead CIFS session                                                      | `sudo umount -l /mnt/pgbackrest-repo && sudo mount -a`                                                                             |
| Share not mounting at boot                                   | Network not up yet                                                     | Keep `_netdev` and `x-systemd.automount`; check `journalctl -u mnt-pgbackrest\\x2drepo.automount`                                  |

Useful diagnostics:

```bash
# host
sudo testparm -s
sudo smbstatus
sudo journalctl -u smbd -n 50 --no-pager
ls -la /stale-storage/share-stalestorage/pgbackrest_backups/archive

# VM
mount | grep pgbackrest-repo
sudo -u postgres pgbackrest --stanza=sqlred info
tail -n 50 /var/log/pgbackrest/sqlred-archive-push-async.log
```

---

## 9. Final checklist

- [ ] Host: `pgbackrest` user exists, has a Samba password, and owns the repo directory (no `+` ACL marker).
- [ ] Host: old usershare is removed; `[pgbackrest]` share defined in `smb.conf`; `testparm` clean.
- [ ] Host: port 445 reachable only from the VM subnet.
- [ ] VM: share mounted via `/etc/fstab`; `WRITE-OK` test passes as `postgres`.
- [ ] VM: `repo1-path=/mnt/pgbackrest-repo` in `pgbackrest.conf`.
- [ ] VM: `archive_mode=on` and the `archive_command` set; PostgreSQL restarted.
- [ ] `pgbackrest check` passes; first full backup completes; `pgbackrest info` shows it.
- [ ] `pg_stat_archiver.failed_count` is not increasing.
- [ ] Cron jobs for full, diff and check are in place.
- [ ] A restore has been tested at least once.
- [ ] An off-host copy of the repo exists.
