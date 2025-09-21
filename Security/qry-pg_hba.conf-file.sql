/*
-- reload cluster settings
select pg_reload_conf();

-- pg_hba.conf settings can be found in [Security/users-roles.sql]
*/

select r.line_number, r.type, r.database, r.user_name,
        r.address, r.netmask, r.auth_method
        --, r.file_name
from pg_hba_file_rules as r;

/*
+-------+----------------+--------------+---------------+-----------------------------------------+---------------+
| Type  |   Database     | User Name    |   Address     |              Netmask                    | Auth Method   |
+-------+----------------+--------------+---------------+-----------------------------------------+---------------+
| local | ["all"]        | ["all"]      | NULL          | NULL                                    | peer          |
| local | ["replication"]| ["all"]      | NULL          | NULL                                    | peer          |
| host  | ["replication"]| ["all"]      | 127.0.0.1     | 255.255.255.255                         | scram-sha-256 |
| host  | ["replication"]| ["all"]      | ::1           | ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff | scram-sha-256 |
| host  | ["all"]        | ["postgres"] | 127.0.0.1     | 255.255.255.255                         | scram-sha-256 |
| host  | ["all"]        | ["postgres"] | ::1           | ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff | scram-sha-256 |
| host  | ["all"]        | ["postgres"] | 192.168.0.0   | 255.255.0.0                             | scram-sha-256 |
| host  | ["all"]        | ["postgres"] | 0.0.0.0       | 0.0.0.0                                 | reject        |
| host  | ["all"]        | ["postgres"] | ::            | ::                                      | reject        |
| host  | ["all"]        | ["all"]      | 0.0.0.0       | 0.0.0.0                                 | scram-sha-256 |
| host  | ["all"]        | ["all"]      | ::            | ::                                      | scram-sha-256 |
+-------+----------------+--------------+---------------+-----------------------------------------+---------------+
*/