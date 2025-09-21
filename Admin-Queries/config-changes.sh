# set autovacuum off
show autovacuum;
\x
select name, setting, context, pending_restart from pg_settings where name = 'autovacuum';

alter system set autovacuum = off;

select name, setting, context, pending_restart from pg_settings where name = 'autovacuum';

select pg_reload_conf();

select name, setting, context, pending_restart from pg_settings where name = 'autovacuum';


autovacuum = 'on'
max_parallel_workers = '4'
max_parallel_workers_per_gather = '2'

session_preload_libraries = 'auto_explain'
auto_explain.log_min_duration = '5s'
auto_explain.log_format = 'json'
auto_explain.log_verbose = 'on'
auto_explain.log_analyze = 'on'
auto_explain.log_buffers = 'on'
auto_explain.log_wal = 'on'
auto_explain.log_timing = 'on'
auto_explain.log_settings = 'on'
shared_preload_libraries = 'pg_stat_statements'    # (change requires restart)

logging_collector = on
log_destination = 'stderr'
log_directory = 'log'
#log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_filename = 'postgresql-%a.log'
log_rotation_age = '1d'
log_rotation_size = '50MB'

log_min_messages = 'info'
client_min_messages = 'warning'

log_min_duration_statement = '5s'
log_min_duration_sample = '2s'
log_statement_sample_rate = 0.1
log_transaction_sample_rate = 0.1

log_temp_files = '20MB'

# Indicate locking issues
log_lock_waits = on
deadlock_timeout = '5s'

log_line_prefix = '%m [%p] %a@@%h [%l] %q%u@%d '
# default
log_line_prefix = '%m [%p] %q%u@%d '


2025-03-26 09:07:51.728 IST [1239322] saanvi@stackoverflow2010 LOG:  duration: 5007.333 ms  statement: select pg_sleep(5);
2025-03-26 09:08:02.400 IST [1239322] saanvi@stackoverflow2010 ERROR:  syntax error at or near "selectt" at character 1
2025-03-26 09:08:02.400 IST [1239322] saanvi@stackoverflow2010 STATEMENT:  selectt 1;
2025-03-26 09:12:14.689 IST [1236230] LOG:  checkpoint starting: time