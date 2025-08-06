# Chp#16 - Configuring and Monitoring
- [pgtune](https://pgtune.leopard.in.ua/)
- [pgconfig](https://www.pgconfig.org/#/?max_connections=100&pg_version=16&environment_name=WEB&total_ram=4&cpus=2&drive_type=SSD&arch=x86-64&os_type=linux)

## Modifying the configuration from live system
```
-- set configuration from cluster
alter system set archive_mode = 'on';

    -- This will add a setting in postgresql.auto.conf file

-- with DEFAULT, the option will be removed from postgresql.auto.conf
alter system set archive_mode to DEFAULT;

-- with RESET/RESET ALL, the option(s) values are set to previous values
alter system RESET archive_mode;
alter system RESET ALL;

-- check settings
select name, setting, unit, short_desc, context, source, boot_val, reset_val, sourcefile, pending_restart
from pg_settings;

```

## Logging and Auditing
```
logging_collection = on
log_destination = 'stderr'
log_directory = 'log'
#log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_filename = 'postgresql-%a.log'
log_rotation_age = '1d'
log_rotation_size = '50MB'

log_min_messages = 'info'
client_min_messages = 'debug1'

log_min_duration_statement = '5s'
log_min_duration_sample = '2s'
log_min_sample_rate = 0.1
log_transactions_sample_rate = 0.1
```


