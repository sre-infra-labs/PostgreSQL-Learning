## 11. pgBadger setup

### 11.1 pgbadger part 01: Setup Multi-Server pgbadger environment on localhost ryzen9 (ubuntu 26) machine

See `Setup-Configuration/pgBadger-settings.md`:

```bash
sudo apt install pgbadger -y
sudo mkdir -p /var/lib/pgbadger/data/html
sudo chown -R postgres:www-data /var/lib/pgbadger/
sudo chmod 770 -R /var/lib/pgbadger/
```

### 11.2 pgbadger part 02: Add the PostgreSQL cluster to above pgbadger environment

Use the logging settings in [section 3](03-logging.md), then import the logs:

```bash
pgbadger -o /var/lib/pgbadger/data/html/first_report.html /var/log/postgresql/postgresql*
```

Incremental import from a remote host:

```bash
pgbadger -I --outdir /var/lib/pgbadger/data/html/<pg-server-hostname> ssh://postgres@<pg-server-hostname>//var/log/postgresql/postgresql*
```

The SSH user needs read access to the logs and passwordless SSH key login (see [section 12](12-passwordless-ssh.md)).
