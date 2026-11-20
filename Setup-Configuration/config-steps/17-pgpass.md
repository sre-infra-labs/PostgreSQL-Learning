## 17. Set up ~/.pgpass for your user and the postgres user

`~/.pgpass` stores connection passwords so `psql`, `pg_dump`, `pgbackrest` checks and scripts stop prompting. libpq reads it only when the file has permission `0600` (or stricter), otherwise it ignores it.

Format (one line per connection, `*` matches any value):

```text
hostname:port:database:username:password
```

Reference: https://www.postgresql.org/docs/current/libpq-pgpass.html

### 17.1 For your default OS user ($USER)

Replace `<db-user>` with the PostgreSQL role that matches `$USER` (create it first if it does not exist: `sudo -u postgres createuser --pwprompt <db-user>`).

```bash
echo "$USER"                   # confirm the OS user name
touch ~/.pgpass
chmod 0600 ~/.pgpass
nano ~/.pgpass
```

Add these lines (type the real password yourself, do not commit it to the repo):

```text
localhost:5432:*:<db-user>:<password>
127.0.0.1:5432:*:<db-user>:<password>
```

### 17.2 For the postgres user

The `postgres` OS user's home directory is `/var/lib/postgresql` on Ubuntu/Debian. Edit its file as `postgres` so the ownership stays correct:

```bash
sudo -u postgres touch ~postgres/.pgpass
sudo -u postgres chmod 0600 ~postgres/.pgpass
sudo -u postgres nano ~postgres/.pgpass
```

Add (the password is the one set in section 0 with `ALTER USER postgres PASSWORD`):

```text
localhost:5432:*:postgres:<password>
127.0.0.1:5432:*:postgres:<password>
```

### 17.3 Verify

Each command should connect without a password prompt:

```bash
psql -h localhost -U "$USER" -d postgres -c 'SELECT current_user;'
sudo -u postgres psql -h localhost -U postgres -d postgres -c 'SELECT current_user;'
```

If it still prompts, check the file permissions (`ls -l ~/.pgpass` must show `-rw-------`), the line format (no spaces, no trailing blank line issues), and that the host in the line matches the host you connect to. Also check `pg_hba.conf` allows `scram-sha-256` for that host (see [section 1](01-tcp-connections.md)).

Note: section 14 suggests `PGPASSWORD` in `~/.bashrc`. Prefer `~/.pgpass` instead, as it is already recommended there.
