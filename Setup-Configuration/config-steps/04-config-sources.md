## 4. Find out the active config value source file

```sql
-- check setting details
SELECT name, setting, unit, source, sourcefile, sourceline
FROM pg_settings
WHERE name = 'shared_preload_libraries';

-- check setting source
SELECT sourcefile, sourceline, seqno, name, setting, applied
FROM pg_file_settings
WHERE name = 'shared_preload_libraries';

-- find every setting that is NOT at its default value
SELECT name, setting, unit, source, sourcefile, sourceline
FROM pg_settings
WHERE source NOT IN ('default', 'override')
ORDER BY sourcefile, name;

-- find settings set at database or role level
SELECT d.datname AS database, r.rolname AS role, s.setconfig
FROM pg_db_role_setting s
LEFT JOIN pg_database d ON d.oid = s.setdatabase
LEFT JOIN pg_roles r ON r.oid = s.setrole;

-- get some common settings
SHOW config_file;
SHOW hba_file;
SHOW data_directory;
SHOW log_destination;
SHOW log_directory;
SHOW log_filename;
SHOW shared_preload_libraries;
```

Check whether a change needs a restart or only a reload:

```sql
SELECT name, context FROM pg_settings WHERE name IN ('shared_buffers','work_mem','listen_addresses','shared_preload_libraries');
-- context = postmaster -> restart; sighup -> pg_reload_conf(); user/superuser -> session level
```

Reload after editing files:

```sql
SELECT pg_reload_conf();
```

Settings made with `ALTER SYSTEM` go to `postgresql.auto.conf`. Remove one with `ALTER SYSTEM RESET <name>;` or all with `ALTER SYSTEM RESET ALL;`.
