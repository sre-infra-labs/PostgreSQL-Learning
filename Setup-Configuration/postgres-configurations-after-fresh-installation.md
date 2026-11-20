# Instructions for configurations required after fresh postgres installation

Work through the steps in order. Each step is in its own file in [config-steps/](config-steps/).

- [Conventions and paths](config-steps/conventions.md)
- [0. Verify the server is up and find the config files](config-steps/00-verify-server.md)
- [1. Enable TCP connections for remote devices](config-steps/01-tcp-connections.md)
- [2. Memory and resource settings](config-steps/02-memory-resources.md)
- [3. Logging](config-steps/03-logging.md)
- [4. Find out the active config value source file](config-steps/04-config-sources.md)
- [5. Extensions](config-steps/05-extensions.md)
- [6. Set up database maintenance jobs using pg_cron](config-steps/06-pg-cron-jobs.md)
- [7. Enable vacuuming (autovacuum)](config-steps/07-autovacuum.md)
- [8. Enable stats collection](config-steps/08-stats-collection.md)
- [9. Backups with pgBackRest](config-steps/09-pgbackrest.md)
- [10. Configure pg_exporter and add to Prometheus](config-steps/10-pg-exporter-prometheus.md)
- [11. pgBadger setup](config-steps/11-pgbadger.md)
- [12. Passwordless SSH between hosts (for remote log / backup access)](config-steps/12-passwordless-ssh.md)
- [13. Install and configure pgwatch](config-steps/13-pgwatch.md)
- [14. Shell and psql conveniences](config-steps/14-shell-psql.md)
- [15. Restore sample databases](config-steps/15-restore-sample-dbs.md)
- [16. Final verification checklist](config-steps/16-final-verification.md)
- [17. Set up ~/.pgpass for your user and the postgres user](config-steps/17-pgpass.md)
- [18. Configure PgBouncer (connection pooler)](config-steps/18-pgbouncer.md)

