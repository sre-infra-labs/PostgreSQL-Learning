# Configuring PostgreSQL Logging for pgBadger usage

## Instal pgbadger
```
sudo apt install pgbadger -y
pgbader --version
```

## Set directory for pgbadger
```
sudo mkdir -p /var/lib/pgbadger/data/html
sudo chown -R postgres:www-data /var/lib/pgbadger/
sudo chmod 770 -R /var/lib/pgbadger/
```

## Settings for generating logs compatible for pgBadger
```
logging_collector = on
log_destination = 'stderr,csvlog,jsonlog'
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = '1d'
log_rotation_size = '50MB'

log_min_duration_statement = 500
log_min_duration_sample = 100
log_statement_sample_rate = 0.8
log_transaction_sample_rate = 0.5
```

## Import logs one time in pgbadger
```
ls -l /var/log/postgresql/
    total 4
    -rw-r----- 1 postgres adm       76791 Mar 26 19:51 postgresql-16-main.log
    -rw-r----- 1 postgres adm      197218 Mar 23 06:09 postgresql-16-main.log.1
    -rw------- 1 postgres postgres   5378 Mar 25 22:06 postgresql-Tue.log
    -rw------- 1 postgres postgres   1766 Mar 26 07:10 postgresql-Wed.log

pgbadger -o /var/lib/pgbadger/data/html/first_report.html /var/log/postgresql/postgresql*
pgbadger -o /var/lib/pgbadger/data/html/first_report.html /var/lib/postgresql/16/main/log/postgresql*
```

# Incremental logs import in pgbadger from remote host pgprod
```
pgbadger -I --outdir /data/html/pgprod ssh://postgres@pgprod//var/log/postgresql/postgresql*
```
>[!IMPORTANT] The remote user used in ssh should have access to the logs and perform an SSH key exchange.

