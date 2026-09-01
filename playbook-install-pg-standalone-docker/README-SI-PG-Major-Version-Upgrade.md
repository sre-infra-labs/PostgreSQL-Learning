# PostgreSQL Major-Version Upgrade to 18

This runbook upgrades the PostgreSQL cluster in the existing `docpg-standalone`
container to PostgreSQL 18 using `pg_upgrade --copy`. It is tailored to this
repository's Ubuntu/PGDG packages, systemd service, Docker volumes, and
versioned data-directory layout.

PostgreSQL 18 supports `pg_upgrade` from PostgreSQL 9.2 and later. This guide
assumes a standalone server with no replicas. Test the procedure on a clone
before using it for important data.

Official reference: <https://www.postgresql.org/docs/18/pgupgrade.html>

## Critical warnings

1. **Do not only change `postgresql_version` and run the full installation
   playbook.** Its precheck can enable `reinit_cluster` when the target data
   directory is non-empty and delete that directory.
2. Do not pass `-e reinit_cluster=true` or
   `-e cleanup_pgbackrest_backups=true` during an upgrade.
3. Do not run `playbook-cleanup.yml` or remove PostgreSQL Docker volumes.
4. This guide uses `--copy`, not `--link` or `--swap`. It needs space for both
   clusters but leaves the old cluster available for rollback.
5. Expect downtime from the source shutdown until PostgreSQL 18 is validated.

## Repository layout

| Item                  | Value                                    |
| --------------------- | ---------------------------------------- |
| Container             | `docpg-standalone`                       |
| Old data directory    | `/var/lib/postgresql/<OLD_MAJOR>/main`   |
| PG18 data directory   | `/var/lib/postgresql/18/main`            |
| Versioned binaries    | `/usr/lib/postgresql/<MAJOR>/bin`        |
| systemd unit          | `/etc/systemd/system/postgresql.service` |
| pgBackRest stanza     | `default`                                |
| pgBackRest repository | `/var/lib/pgbackrest`                    |

## Start an interactive container shell

Run this one command on the host, then perform the rest of the runbook inside
the container as `root`:

```bash
docker exec -it -u root docpg-standalone bash
```

Inside the container, commands that access PostgreSQL or pgBackRest use the
`postgres` OS account through `runuser -u postgres --`. Upgrade artifacts are
stored under `/var/lib/postgresql/upgrade-backups`, which is on the PostgreSQL
data volume. The final Ansible source-file update is the only host-side step.

## 1. Define and verify variables

```bash
TARGET_MAJOR=18
OLD_MAJOR=$(runuser -u postgres -- psql -h localhost -U postgres -Atqc \
  "SHOW server_version_num" | awk '{print int($1 / 10000)}')
OLD_DATA="/var/lib/postgresql/${OLD_MAJOR}/main"
NEW_DATA="/var/lib/postgresql/${TARGET_MAJOR}/main"
OLD_BIN="/usr/lib/postgresql/${OLD_MAJOR}/bin"
NEW_BIN="/usr/lib/postgresql/${TARGET_MAJOR}/bin"
BACKUP_DIR="/var/lib/postgresql/upgrade-backups/pg${OLD_MAJOR}-to-pg${TARGET_MAJOR}-$(date '+%Y-%m-%d__%H_%M_%S')"

printf 'Source: PG%s %s\nTarget: PG%s %s\n' \
  "$OLD_MAJOR" "$OLD_DATA" "$TARGET_MAJOR" "$NEW_DATA"
test "$OLD_MAJOR" -lt "$TARGET_MAJOR"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
```

Confirm the source and its data directory:

```bash
runuser -u postgres -- psql -h localhost -U postgres -x -c \
  "SELECT version(), current_setting('data_directory') AS data_directory;"
test -f "$OLD_DATA/PG_VERSION"
cat "$OLD_DATA/PG_VERSION"
findmnt -T /var/lib/postgresql || df -h /var/lib/postgresql
```

Stop if the reported major version, path, container, or volume is not intended.

## 2. Inventory health and compatibility

`lc_collate`/`lc_ctype` were removed as server-level GUCs in PostgreSQL 16
(`SHOW lc_collate` now errors with `unrecognized configuration parameter`).
Query them per-database from `pg_database` instead:

```bash
runuser -u postgres -- psql -h localhost -U postgres -Atqc \
  "SHOW server_version; SHOW data_directory;" \
  > "$BACKUP_DIR/source-settings.txt"

runuser -u postgres -- psql -h localhost -U postgres -Atqc \
  "SELECT datname, datcollate, datctype FROM pg_database ORDER BY 1;" \
  >> "$BACKUP_DIR/source-settings.txt"

runuser -u postgres -- psql -h localhost -U postgres -P pager=off -c \
  "SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
     FROM pg_database ORDER BY pg_database_size(datname) DESC;" \
  > "$BACKUP_DIR/database-sizes.txt"

runuser -u postgres -- psql -h localhost -U postgres -P pager=off -c \
  "SELECT extname, extversion FROM pg_extension ORDER BY 1;" \
  > "$BACKUP_DIR/extensions.txt"

runuser -u postgres -- psql -h localhost -U postgres -P pager=off -c \
  "SELECT slot_name, slot_type, active FROM pg_replication_slots;" \
  > "$BACKUP_DIR/replication-slots.txt"

runuser -u postgres -- "$OLD_BIN/pg_controldata" "$OLD_DATA" \
  > "$BACKUP_DIR/pg_controldata-before.txt"
```

Review `extensions.txt`. Install a PG18 binary package for every extension
using a shared library. This playbook requires `pg_cron`; `dblink` and
`pg_stat_statements` are supplied by `postgresql-contrib-18`.

## 3. Take recoverable backups

These logical dumps can contain password hashes and database data. Keep them
mode `0600` and do not commit them.

```bash
runuser -u postgres -- pg_dumpall --globals-only \
  > "$BACKUP_DIR/globals.sql"
runuser -u postgres -- pg_dumpall \
  > "$BACKUP_DIR/all-databases.sql"
chmod 600 "$BACKUP_DIR"/*.sql
```

The role now configures WAL archiving. Take and verify a pgBackRest backup:

```bash
runuser -u postgres -- \
  pgbackrest --stanza=default check
runuser -u postgres -- \
  pgbackrest --stanza=default --type=full backup
runuser -u postgres -- \
  pgbackrest --stanza=default info
```

Do not proceed if either logical dump or the required pgBackRest backup fails.

## 4. Install PostgreSQL 18 and extension packages

The PGDG repository is configured by this project.

```bash
apt-get update
apt-get install -y \
  postgresql-18 postgresql-client-18 postgresql-contrib-18 \
  postgresql-server-dev-18 postgresql-18-cron
```

Install PG18 variants of additional extensions listed in `extensions.txt`,
such as `postgresql-18-partman` when that extension is actually installed.

Ubuntu may automatically create an empty `18/main` cluster. Remove only that
empty target before initializing it:

```bash
systemctl stop postgresql@18-main 2>/dev/null || true
if [ -d /etc/postgresql/18/main ]; then
  pg_dropcluster --stop 18 main
fi
test ! -e "$NEW_DATA"
"$NEW_BIN/postgres" --version
```

## 5. Initialize the empty PG18 target

This playbook uses UTF-8, `C.UTF-8`, and data checksums. Use the same settings
as the source; if the saved source settings differ, match those instead.

```bash
install -d -o postgres -g postgres \
  "$(dirname "$NEW_DATA")"
runuser -u postgres -- "$NEW_BIN/initdb" \
  --pgdata="$NEW_DATA" \
  --encoding=UTF8 \
  --locale=C.UTF-8 \
  --data-checksums
```

## 6. Stop the source and create a cold copy

Block application access, then stop PostgreSQL cleanly:

```bash
systemctl stop postgresql
runuser -u postgres -- "$OLD_BIN/pg_ctl" \
  -D "$OLD_DATA" status; test $? -eq 3
```

Create a container-local archive while the source is stopped:

```bash
tar -C /var/lib/postgresql -czf - \
  "$OLD_MAJOR" > "$BACKUP_DIR/pg${OLD_MAJOR}-cold.tar.gz"
sha256sum "$BACKUP_DIR/pg${OLD_MAJOR}-cold.tar.gz" \
  > "$BACKUP_DIR/pg${OLD_MAJOR}-cold.tar.gz.sha256"
du -sh "$OLD_DATA"
df -h /var/lib/postgresql
```

With `--copy`, free space must accommodate both clusters.

## 7. Run `pg_upgrade --check`

Always use the PG18 `pg_upgrade` binary:

```bash
runuser -u postgres -- bash -lc \
  "cd /var/lib/postgresql && '$NEW_BIN/pg_upgrade' --check --copy \
    --old-bindir='$OLD_BIN' --new-bindir='$NEW_BIN' \
    --old-datadir='$OLD_DATA' --new-datadir='$NEW_DATA' \
    --username=postgres --jobs=2"
```

Resolve every reported incompatibility, especially missing PG18 extension
libraries. Never remove the old data directory to resolve a failed check.

## 8. Perform the upgrade

```bash
runuser -u postgres -- bash -lc \
  "cd /var/lib/postgresql && '$NEW_BIN/pg_upgrade' --copy \
    --old-bindir='$OLD_BIN' --new-bindir='$NEW_BIN' \
    --old-datadir='$OLD_DATA' --new-datadir='$NEW_DATA' \
    --username=postgres --jobs=2"
```

Save the output and inspect any scripts under
`/var/lib/postgresql/pg_upgrade_output.d`. Do not start either cluster if the
upgrade fails; fix the cause or roll back.

## 9. Restore configuration and point the service to PG18

Do not copy `postgresql.conf` wholesale because removed parameters may prevent
PG18 from starting. Preserve the authentication and Ansible-managed settings:

```bash
cp \
  "$OLD_DATA/postgresql.auto.conf" "$NEW_DATA/postgresql.auto.conf"
cp \
  "$OLD_DATA/pg_hba.conf" "$NEW_DATA/pg_hba.conf"
chown postgres:postgres \
  "$NEW_DATA/postgresql.auto.conf" "$NEW_DATA/pg_hba.conf"

sed -i \
  -e "s#/usr/lib/postgresql/${OLD_MAJOR}/bin#/usr/lib/postgresql/18/bin#g" \
  -e "s#/var/lib/postgresql/${OLD_MAJOR}/main#/var/lib/postgresql/18/main#g" \
  /etc/systemd/system/postgresql.service

sed -i \
  "s#/var/lib/postgresql/${OLD_MAJOR}/main#/var/lib/postgresql/18/main#g" \
  /etc/pgbackrest/pgbackrest.conf
systemctl daemon-reload
```

## 10. Start and validate PG18

```bash
systemctl start postgresql
systemctl --no-pager --full status postgresql
runuser -u postgres -- psql -h localhost -U postgres -x -c \
  "SELECT version(), current_setting('data_directory') AS data_directory;"
runuser -u postgres -- psql -h localhost -U postgres -Atqc \
  "SELECT count(*) FROM pg_database WHERE datallowconn;"
runuser -u postgres -- psql -h localhost -U postgres -Atqc \
  "SELECT datname, datcollate, datctype FROM pg_database ORDER BY 1;"
```

Confirm the version starts with `PostgreSQL 18` and the data directory is
`/var/lib/postgresql/18/main`. Compare the collation/ctype output against
`$BACKUP_DIR/source-settings.txt` from step 2. Validate application logins,
database counts, row counts, extensions, scheduled jobs, and representative
read/write traffic.

`pg_upgrade` may report `Checking for extension updates ... notice` and write
`update_extensions.sql` to the directory it was run from
(`/var/lib/postgresql`). Apply it against every database (add `\connect` or a
per-database loop if it does not already cover all databases):

```bash
cd /var/lib/postgresql
runuser -u postgres -- psql -h localhost -U postgres \
  -f update_extensions.sql -d postgres
```

Then refresh statistics, since `pg_upgrade` does not transfer them. Use the
versioned `$NEW_BIN/vacuumdb` binary explicitly — the unversioned `vacuumdb`
on `PATH` is a Debian/Ubuntu wrapper that may still target the old cluster
and reject newer flags such as `--missing-stats-only`:

```bash
runuser -u postgres -- "$NEW_BIN/vacuumdb" -h localhost -U postgres --all \
  --analyze-in-stages --missing-stats-only --jobs=2
runuser -u postgres -- "$NEW_BIN/vacuumdb" -h localhost -U postgres --all \
  --analyze-only --jobs=2
```

## 11. Upgrade pgBackRest metadata and test a PG18 backup

```bash
runuser -u postgres -- \
  pgbackrest --stanza=default --log-level-console=info stanza-upgrade
runuser -u postgres -- \
  pgbackrest --stanza=default check
runuser -u postgres -- \
  pgbackrest --stanza=default --type=full backup
runuser -u postgres -- \
  pgbackrest --stanza=default info
```

Do not expire old backups until the acceptance and rollback period ends.

## 12. Update Ansible's desired version — HOST ONLY

This is the only operational step that must run **outside the container**.
After PG18 is running and validated, leave the container:

```bash
# INSIDE CONTAINER
exit
```

Then run the following commands in a terminal on the host, from the Ansible
project directory:

```yaml
# vars/dba_vars.yml
postgresql_version: "18"
```

Edit `vars/dba_vars.yml` on the host, then refresh the versioned shell
environment without invoking the installer and its reinitialization prechecks:

```bash
cd /Users/ajaydwivedi/Documents/Github/Personal/PostgreSQL-Learning/playbook-install-pg-standalone-docker
ansible-playbook playbook-install-pg-standalone.yml \
  --vault-password-file=vault-pass --tags container_env
```

Do not run the full installation playbook as an upgrade validation step. The
role is an installer/reinitializer, not a major-upgrade role.

## 13. Rollback before acceptance

Because this procedure used `--copy`, the old cluster remains independent. If
PG18 validation fails:

```bash
systemctl stop postgresql
sed -i \
  -e "s#/usr/lib/postgresql/18/bin#/usr/lib/postgresql/${OLD_MAJOR}/bin#g" \
  -e "s#/var/lib/postgresql/18/main#/var/lib/postgresql/${OLD_MAJOR}/main#g" \
  /etc/systemd/system/postgresql.service
sed -i \
  "s#/var/lib/postgresql/18/main#/var/lib/postgresql/${OLD_MAJOR}/main#g" \
  /etc/pgbackrest/pgbackrest.conf
systemctl daemon-reload
systemctl start postgresql
runuser -u postgres -- psql -h localhost -U postgres -Atqc \
  "SELECT version(), current_setting('data_directory');"
```

Revert `vars/dba_vars.yml` to the old major if it was changed. Writes made to
PG18 after cutover are not present in the old cluster.

## 14. Cleanup after acceptance

After backups are verified and rollback is no longer required:

1. Record final validation and backup evidence.
2. Confirm the active data directory is PG18.
3. Remove the old data directory only after that confirmation.
4. Optionally remove old PostgreSQL and extension packages.
5. Retain logical and pgBackRest backups according to policy.

`pg_upgrade` (step 8) generates `delete_old_cluster.sh` in
`/var/lib/postgresql`. Do not run it until PG18 has been fully validated and
you no longer need the old cluster for rollback:

```bash
cd /var/lib/postgresql
runuser -u postgres -- ./delete_old_cluster.sh
```

Deletion is intentionally not scripted to run automatically because it is
irreversible.