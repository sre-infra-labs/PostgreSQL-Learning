# Conventions and paths

Replace `<ver>` with your major version (for example `16`) and `<cluster>` with the cluster name (usually `main` on Ubuntu/Debian).

Ubuntu/Debian paths used below:
- Config directory: `/etc/postgresql/<ver>/<cluster>/`
- `postgresql.conf`: `/etc/postgresql/<ver>/<cluster>/postgresql.conf`
- `pg_hba.conf`: `/etc/postgresql/<ver>/<cluster>/pg_hba.conf`
- Drop-in config directory: `/etc/postgresql/<ver>/<cluster>/conf.d/` (used for custom settings, e.g. `dba.conf`)
- Data directory: `/var/lib/postgresql/<ver>/<cluster>`

RHEL/Fedora paths are usually `/var/lib/pgsql/<ver>/data/` for data and config.
