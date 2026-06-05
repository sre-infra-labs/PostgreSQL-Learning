# Handling Logical Replication Slots in PostgreSQL Patroni Cluster

## Customer Requests
- https://tessell.atlassian.net/browse/TS-38868
- https://tessell.atlassian.net/browse/TS-31557

## Technical Blogs
- https://www.postgresql.eu/events/pgconfde2022/sessions/session/3745/slides/306/Implementing%20failover%20of%20logical%20replication%20slots%20in%20Patroni.pdf
- https://github.com/sre-infra-labs/PostgreSQL-Learning/blob/dev/Debezium-CDC-Kafka/CDC-Using-Debezium-n-Kafka.md#2-debezium-connector

## Github Branch
- [TS-31557](https://github.com/TessellDevelopment/tessell-database-plugin-postgres/tree/TS-31557)

## Assumptions
- We will be using built-in plugins (test_decoding, pgoutput) for CDC.
- Customer already has `master` superuser database user.

## Technical Summary
- Create a permanent user capable of performing replication operations
  - [Permissions for Replication User]
    - [LOGIN & REPLICATION Role](https://debezium.io/documentation/reference/3.4/connectors/postgresql.html#postgresql-security)
    - [Create Publication Permissions](https://debezium.io/documentation/reference/3.4/connectors/postgresql.html#postgresql-replication-user-privileges)
    - [Logical Replication Security](https://www.postgresql.org/docs/current/logical-replication-security.html)
  - Create Replication User for CDC operations *(cluster-wide — any database context)*
    - `CREATE ROLE replication_admin WITH LOGIN REPLICATION BYPASSRLS PASSWORD 'Pg@Lab2026!';`
  - Create Replication Group for handling table ownership while creating publication *(cluster-wide — any database context)*
    - `CREATE ROLE replication_group;`
    - Grant CREATE privilege on the database to add publication *(cluster-wide — any database context)*
      - `GRANT CREATE ON DATABASE <database_name> TO replication_group;`
    - Grant Privileges to create subscription *(cluster-wide — any database context)*
      - `GRANT pg_create_subscription TO replication_group;`
      - `GRANT CREATE ON DATABASE <database_name> TO replication_group;`
    - Grant SELECT privilege on all tables (Existing & Future) to replication group *(must run under `<database_name>` context)*
      - `GRANT USAGE ON SCHEMA public TO replication_group;`
      - `GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication_group;`
      - `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO replication_group;`
    - Add original owner of the table to the group *(cluster-wide — any database context)*
      - `GRANT replication_group TO <original_owner>;`
    - Add CDC replication user to the group *(cluster-wide — any database context)*
      - `GRANT replication_group TO replication_admin;`
    - Transfer ownership of table to replication group *(must run under `<database_name>` context)*
      - `ALTER TABLE <table_name> OWNER TO replication_group;`
- Configure pg_hba.conf to allow CDC Client Host
  - `local replication replication_admin trust`
  - `host replication replication_admin 127.0.0.1/32 trust`
  - `host replication replication_admin ::1/128 trust`
  - `host replication replication_admin 0.0.0.0/0 scram-sha-256`
- Patroni Configurations to Enable logical replication
  - Consumer inputs
    - Replication Slot Name
    - Output Plugin Name. Assuming Built-in plugins.
      - test_decoding
      - pgoutput
    - Database Name
  - During Service Setup (Patroni Cluster INIT)
    - use_slots: true
    - wal_level = logical
    - max_replication_slots = 10
    - max_wal_senders = 10
    - hot_standby_feedback = on
  - Patroni configuration commands
```
# Switch to Postgres User
sudo su - postgres

# Set basic patroni config
patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-dc1 --force \
  --set "postgresql.parameters.wal_level=logical" \
  --set "postgresql.parameters.wal_log_hints=on" \
  --set "postgresql.parameters.max_replication_slots=10" \
  --set "postgresql.parameters.max_wal_senders=10" \
  --set "postgresql.use_pg_rewind=true" \
  --set "postgresql.use_slots=true"

# Set logical replication slot
patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-dc1 --force \
  --set "slots.debezium_slot.type=logical" \
  --set "slots.debezium_slot.database=cdc_db" \
  --set "slots.debezium_slot.plugin=test_decoding"

# Creates/replaces the entire pg_hba list in the DCS — Patroni regenerates pg_hba.conf and sends SIGHUP
patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-dc1 --force \
  --set 'postgresql.pg_hba=["local all postgres peer",
    "host all all 127.0.0.1/32 scram-sha-256",
    "host replication replicator 0.0.0.0/0 scram-sha-256",
    "host replication replication 172.18.0.0/16 scram-sha-256",
    "host all all 0.0.0.0/0 scram-sha-256",
    "host all all ::/0 scram-sha-256"]'
```


### PG Nodes
```
primary - 13.232.104.164
replica - 15.207.220.73
dr replica - 13.207.111.129
```

Technical Aspects to Discuss -- What plugins we want to support (pgoutput, test_decoding)?
- How to handle plugin, database, slot_name input
- How to handle input of db user required for replication
- What is cardinality of required objects?
   - Only single slot, plugin, database, db_user per cluster, or multiple of any of these combinations?
- How to handle snapshot & tables ownership while creating publication?
- Post slot addition, how to handle "pending restart"
- How to handle entry in "pg_hba.conf" file.


---

# Logical Replication Setup (Publisher → Subscriber)

## Environment

| Role       | Container  | IP            | Port   | Notes.                |
|------------|------------|---------------|--------|-----------------------|
| Publisher  | `pg1`      | `172.18.0.11` | `5432` | Patroni primary node  |
| Subscriber | `postgres` | `172.18.0.21` | `5432` | Standalone PostgreSQL |

> All containers are on `lab-network` bridge.

---

## Step 1 - On Publisher/Subscriber - By DBA - For Customer - Create database & User for Application Team

Create a database `cdc_db` and login `master` for Customer.

```sql
-- Connect to server as DBA
docker exec -it pg1 bash
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -U postgres -d postgres

-- Check databases
\l

-- Create database
CREATE DATABASE cdc_db;

-- Create master login for customer with DDL/DML permissions on cdc_db
CREATE ROLE master WITH LOGIN SUPERUSER ENCRYPTED PASSWORD 'Pg@Lab2026!';

-- Create replication user for customer
CREATE ROLE replication_admin WITH LOGIN REPLICATION BYPASSRLS ENCRYPTED PASSWORD 'Pg@Lab2026!';

-- Create replication group for handling table ownership while creating publication
CREATE ROLE replication_group;

-- Add CDC replication user to the group
GRANT replication_group TO replication_admin WITH ADMIN OPTION;
GRANT replication_group TO master WITH ADMIN OPTION;

-- Grant pg_create_subscription (required to create subscription on subscriber)
GRANT pg_create_subscription TO replication_group;


--
-- Create replication slot config table
--
\c postgres

CREATE EXTENSION IF NOT EXISTS citext;
CREATE SCHEMA IF NOT EXISTS dba;

CREATE TABLE dba.replication_slot_config (
    slot_name   citext      PRIMARY KEY,
    plugin      citext      NOT NULL,
    database    citext      NOT NULL,
    desired     boolean     NOT NULL DEFAULT true,
    created_by  text        NOT NULL DEFAULT current_user,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

--
-- Audit/decision log written by repl_slot_manager.py each run.
-- One row per observed fact or action; all rows for a single run share the same run_id.
--
CREATE TABLE dba.replication_slot_config_log (
    id           bigserial    PRIMARY KEY,
    run_id       uuid         NOT NULL,                      -- groups all events for one script execution
    logged_at    timestamptz  NOT NULL DEFAULT now(),
    hostname     text         NOT NULL,                      -- node that ran the script
    cluster_name text         NOT NULL,                      -- Patroni cluster scope
    event_type   text         NOT NULL,                      -- see values below
    slot_name    citext,                                     -- populated for slot-related events
    plugin       citext,                                     -- populated for slot-related events
    database     citext,                                     -- populated for slot-related events
    wal_level    text,                                       -- populated for wal_level events
    desired      boolean,                                    -- from dba.replication_slot_config (true/false)
    scenario     text,                                       -- 'Scenario 01' / 'Scenario 03'
    message      text         NOT NULL                       -- human-readable detail
);

-- event_type reference values:
--   START                   script started on the leader node (logged after leader check passes)
--   WAL_LEVEL_PG            observed wal_level from PostgreSQL (SHOW wal_level)
--   WAL_LEVEL_PATRONI       observed wal_level from Patroni DCS config
--   SLOT_PATRONI            logical slot found in Patroni DCS config
--   SLOT_CONFIG_DESIRED     slot in dba.replication_slot_config with desired = true
--   SLOT_CONFIG_UNDESIRED   slot in dba.replication_slot_config with desired = false
--   SLOT_ADDED              slot added to Patroni DCS config (patronictl edit-config)
--   SLOT_REMOVED            slot removed from Patroni DCS config (patronictl edit-config)
--   WAL_LEVEL_SET_LOGICAL   full CDC parameters applied to Patroni DCS config
--   WAL_LEVEL_REVERTED      wal_level reverted to replica in Patroni DCS config
--   SCENARIO                scenario evaluation result
--   SUMMARY                 final summary row for the run
--   FINISH                  script completed successfully (logged after SUMMARY)
--   ERROR                   unexpected error during the run

CREATE INDEX ON dba.replication_slot_config_log (run_id);
CREATE INDEX ON dba.replication_slot_config_log (logged_at);
CREATE INDEX ON dba.replication_slot_config_log (event_type);
```

## Step 2 - On Publisher - By Customer (master) - Create tables

Customer creates application tables in `cdc_db` database.

```sql
-- Connect to database as master
docker exec -it pg1 bash
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -U master -d cdc_db

\c cdc_db
select current_user;

-- Create tables
CREATE TABLE public.customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE TABLE public.orders (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES public.customers(id),
    amount NUMERIC(10,2),
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Validate tables. Ensure ownership belong to master
\dt+

```

## Step 3 — On Publisher — By Customer (master) — Configure PostgreSQL for Logical Replication

*Actor: Customer connects as `master` (superuser) via psql — no SSH, no patronictl*
*Context: any database*

```sql
-- Connect to publisher as master
docker exec -it pg1 bash
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -U master -d postgres

\c postgres

-- All three resolve to the same row
INSERT INTO dba.replication_slot_config(slot_name, plugin, database)
VALUES ('Debezium_Slot', 'PgOutput', 'CDC_DB');

SELECT * FROM dba.replication_slot_config WHERE slot_name = 'debezium_slot';   -- ✅ found
SELECT * FROM dba.replication_slot_config WHERE slot_name = 'DEBEZIUM_SLOT';   -- ✅ found

-- Drop slot if required
UPDATE dba.replication_slot_config
SET    desired    = false,
       updated_at = now()
WHERE  slot_name  = 'debezium_slot';

-- Set WAL and replication parameters (all require PostgreSQL restart)
ALTER SYSTEM SET wal_level             = 'logical';
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders       = 10;
ALTER SYSTEM SET wal_log_hints         = on;

-- Verify settings are queued (pending_restart = true means restart needed)
SELECT name, setting, pending_restart, boot_val, reset_val, sourcefile, sourceline
FROM   pg_settings
WHERE  name IN ('wal_level','max_replication_slots','max_wal_senders','wal_log_hints')
ORDER  BY name;
```

Expected output:
```
         name          | setting | pending_restart
-----------------------+---------+-----------------
 max_replication_slots | 8       | t
 max_wal_senders       | 10      | t
 wal_level             | replica | t
 wal_log_hints         | on      | t
```

> Customer can perform SwitchOver/Switchback between Leader & HA replica for pending restart.
> `patronictl -c /etc/patroni/patroni.yml restart pg-docker-dc1 --force`

### Verify after DBA restarts

```sql
psql -h 172.18.0.11 -U master -d postgres

SHOW wal_level;
SHOW max_replication_slots;
SHOW max_wal_senders;
```

Expected output:
```
 wal_level
-----------
 logical

 max_replication_slots
-----------------------
 10

 max_wal_senders
-----------------
 10
```

---

## Step 4 — On Publisher/Subscriber — By Customer (master) — Grant Privileges to Replication Group

*Actor: Customer connects as `master` (superuser) via psql*

> `replication_admin`, `replication_group`, and `GRANT replication_group TO replication_admin WITH ADMIN OPTION` were already done in Step 1 by DBA.

```sql
-- Connect to publisher as master
docker exec -it pg1 bash
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -U master -d postgres

\c postgres

-- *** Cluster-wide — any DB context ***

-- Grant CREATE on database (required to create publication)
GRANT CREATE ON DATABASE cdc_db TO replication_group;

-- *** Must run under cdc_db context ***
\c cdc_db

-- Grant schema usage and SELECT on all tables (existing & future)
GRANT USAGE ON SCHEMA public TO replication_group;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication_group;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO replication_group;
```

### Verify group membership

```sql
\c postgres
\du+ replication_admin
\du+ replication_group
```

Expected output:
```
                               List of roles
         Role name         |          Attributes          |      Member of
---------------------------+------------------------------+--------------------
 replication_admin         | Replication, Bypass RLS      | {replication_group}

       Role name      | Attributes | Member of
----------------------+------------+-----------
 replication_group    |            | {}
```

---

## Step 5 — On Publisher — By Customer (master) — Set REPLICA IDENTITY & Transfer Table Ownership

*Actor: Customer connects as `master` (superuser) via psql*
*Context: `cdc_db`*

```sql
-- Connect to publisher cdc_db as master
docker exec -it pg1 bash
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -U master -d cdc_db

\c cdc_db

-- Set REPLICA IDENTITY FULL (required for UPDATE/DELETE to capture old row values)
ALTER TABLE public.customers REPLICA IDENTITY FULL;
ALTER TABLE public.orders   REPLICA IDENTITY FULL;

-- Transfer table ownership to replication_group
-- (required so replication_admin can create publication for these tables)
ALTER TABLE public.customers OWNER TO replication_group;
ALTER TABLE public.orders   OWNER TO replication_group;
```

### Verify REPLICA IDENTITY and ownership

```sql
SELECT relname, relreplident, relowner::regrole AS owner
FROM   pg_class
WHERE  relname IN ('customers','orders')
ORDER  BY relname;
```

Expected output:
```
  relname  | relreplident |      owner
-----------+--------------+------------------
 customers | f            | replication_group
 orders    | f            | replication_group
```

> `f` = FULL, `d` = DEFAULT, `n` = NOTHING, `i` = INDEX

### Revert REPLICA IDENTITY (if needed)

```sql
ALTER TABLE public.customers REPLICA IDENTITY DEFAULT;
ALTER TABLE public.orders   REPLICA IDENTITY DEFAULT;
```

---

## Step 6 — On Publisher — By DBA — Add pg_hba.conf Entry for Replication

*Actor: DBA via patronictl — customer cannot do this (no SSH access)*

```bash
# DBA adds entry via Patroni DCS config (no direct file edit needed)
patronictl -c /etc/patroni/patroni.yml edit-config pg-docker-dc1 --force \
  --set 'postgresql.pg_hba=["local all postgres peer",
    "local replication all trust",
    "host replication all 127.0.0.1/32 trust",
    "host replication all ::1/128 trust",
    "host replication all 0.0.0.0/0 scram-sha-256",
    "host replication all ::/0 scram-sha-256",
    "host all all 0.0.0.0/0 scram-sha-256",
    "host all all ::/0 scram-sha-256"]'

su - postgres
vim ./18/main/pg_hba.conf


local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust

local   all             postgres                                peer

host    replication     all             0.0.0.0/0               scram-sha-256
host    replication     all             ::/0                    scram-sha-256
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
```

### Verify pg_hba entry is active

```sql
-- Customer verifies via psql as master
psql -h 172.18.0.11 -U master -d postgres

SELECT type, database, user_name, address, auth_method
FROM   pg_hba_file_rules
WHERE  user_name::text LIKE '%replication_admin%';
```

Expected output:
```
 type | database      | user_name           | address   | auth_method
------+---------------+---------------------+-----------+--------------
 host | {replication} | {replication_admin} | 0.0.0.0/0 | scram-sha-256
```

---

## Step 7 — On Publisher — By Debezium/Customer (replication_admin) — Create Publication & Replication Slot

*Actor: Customer connects as `replication_admin` via psql (simulating Debezium)*
*Context: `cdc_db`*

```sql
-- Connect to publisher cdc_db as replication_admin
docker exec -it pg1 bash
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -U replication_admin -d cdc_db

\c cdc_db

-- Create publication for DML changes on captured tables
CREATE PUBLICATION cdc_publication FOR TABLE public.customers, public.orders;

-- Create logical replication slot for Debezium
SELECT * FROM pg_create_logical_replication_slot('debezium_slot', 'pgoutput');
```

Expected output:
```
CREATE PUBLICATION
    slot_name    |    lsn
-----------------+------------
 debezium_slot   | 0/1234ABCD
(1 row)
```

### Verify publication

```sql
SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete, pubtruncate
FROM   pg_publication
WHERE  pubname = 'cdc_publication';
```

Expected output:
```
     pubname     | puballtables | pubinsert | pubupdate | pubdelete | pubtruncate
-----------------+--------------+-----------+-----------+-----------+-------------
 cdc_publication | f            | t         | t         | t         | t
(1 row)
```

### Verify tables in publication

```sql
SELECT pubname, schemaname, tablename
FROM   pg_publication_tables
WHERE  pubname = 'cdc_publication';
```

Expected output:
```
     pubname     | schemaname | tablename
-----------------+------------+-----------
 cdc_publication | public     | customers
 cdc_publication | public     | orders
(2 rows)
```

### Verify replication slot

```sql
SELECT slot_name, plugin, slot_type, database, active
FROM   pg_replication_slots
WHERE  slot_name = 'debezium_slot';
```

Expected output:
```
   slot_name   |  plugin  | slot_type | database | active
---------------+----------+-----------+----------+--------
 debezium_slot | pgoutput | logical   | cdc_db   | f
(1 row)
```

### Add a table to publication

```sql
ALTER PUBLICATION cdc_publication ADD TABLE public.<new_table>;
```

### Remove a table from publication

```sql
ALTER PUBLICATION cdc_publication DROP TABLE public.<table_name>;
```

### Remove publication and slot (if needed)

```sql
DROP PUBLICATION IF EXISTS cdc_publication;
SELECT pg_drop_replication_slot('debezium_slot');
```

---

## Step 8 — On Subscriber — By Customer (master) — Create Database & Tables

*Actor: Customer connects as `master` (superuser) via psql on Subscriber*
*Context: `postgres` then `cdc_db`*

```sql
-- Connect to subscriber as master
docker exec -it postgres bash
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -U master -d cdc_db

-- IMPORTANT: Assuming database cdc_db, and roles are created on subscriber as done in Step 1.
-- IMPORTANT: Assuming permissions are granted on subscriber as done in Step 4.

-- Connect to cdc_db and create matching tables (schema must match publisher)
\c cdc_db

CREATE TABLE public.customers (
    id           SERIAL PRIMARY KEY,
    name         TEXT NOT NULL,
    email        TEXT,
    created_at   TIMESTAMPTZ DEFAULT NOW()
);
CREATE TABLE public.orders (
    id           SERIAL PRIMARY KEY,
    customer_id  INT,
    amount       NUMERIC(10,2),
    status       TEXT DEFAULT 'pending',
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- Transfer table ownership to replication_group
-- (required as the tablesync worker need replication_admin to be table owner directly/indirectly before initial data copy)
ALTER TABLE public.customers OWNER TO replication_group;
ALTER TABLE public.orders   OWNER TO replication_group;

-- Verify tables
\dt+
```

---

## Step 9 — On Subscriber — By Debezium/Customer (replication_admin) — Create Subscription

*Actor: Customer connects as `replication_admin` via psql on Subscriber (simulating Debezium)*
*Context: `cdc_db`*

```sql
-- Connect to subscriber cdc_db as replication_admin
docker exec -it postgres bash
export PGPASSWORD='Pg@Lab2026!'
psql -h localhost -U replication_admin -d cdc_db

\c cdc_db

-- Create subscription pointing to publisher (writer haproxy ip 172.18.0.10)
-- slot_name must match the slot created in Step 7; create_slot=false reuses existing slot
CREATE SUBSCRIPTION cdc_subscription
    CONNECTION 'host=172.18.0.10 port=5432 dbname=cdc_db user=replication_admin password=Pg@Lab2026!'
    PUBLICATION cdc_publication
    WITH (slot_name = 'debezium_slot', create_slot = false);
```

Expected output:
```
CREATE SUBSCRIPTION
```

### Verify subscription

```sql
SELECT subname, subenabled, subpublications, subslotname
FROM   pg_subscription;
```

Expected output:
```
    subname       | subenabled |  subpublications   |   subslotname
------------------+------------+--------------------+---------------
 cdc_subscription | t          | {cdc_publication}  | debezium_slot
(1 row)
```

### Check subscription status (lag, state)

```sql
\x
SELECT *
FROM   pg_stat_subscription;
```

Expected output:
```
    subname       |  pid  | received_lsn | latest_end_lsn | sender_host
------------------+-------+--------------+----------------+-------------
 cdc_subscription | 12345 | 0/1234ABCD   | 0/1234ABCD     | 172.18.0.11
(1 row)
```

### Enable / Disable subscription

```sql
-- Disable (pause replication)
ALTER SUBSCRIPTION cdc_subscription DISABLE;

-- Enable (resume replication)
ALTER SUBSCRIPTION cdc_subscription ENABLE;
```

### Refresh subscription (pick up newly added tables)

```sql
ALTER SUBSCRIPTION cdc_subscription REFRESH PUBLICATION;
```

### Remove subscription (if needed)

```sql
DROP SUBSCRIPTION IF EXISTS cdc_subscription;
```

> Dropping subscription also drops the replication slot on the publisher automatically.

---

## Step 10 — Verify Replication End-to-End

*Actor: Customer connects as `master` via psql*

### By Customer (master) - Insert data on Publisher

```sql
-- Connect to publisher cdc_db as master
docker exec -it pg1 bash
export PGPASSWORD='Pg@Lab2026!'
psql -h 172.18.0.10 -U master -d cdc_db

\d public.customers
\d public.orders


INSERT INTO public.customers (name, email) VALUES
  ('Alice', 'alice@example.com'),
  ('Bob',   'bob@example.com');

INSERT INTO public.orders (customer_id, amount, status) VALUES
  (1, 99.99, 'completed'),
  (2, 149.50, 'pending');
```

Expected output:
```
INSERT 0 2
INSERT 0 2
```

### Verify data on Subscriber (should replicate within seconds)

```sql
-- Connect to subscriber cdc_db as master
psql -h 172.18.0.21 -U master -d cdc_db

SELECT * FROM public.customers;
SELECT * FROM public.orders;
```

Expected output:
```
 id | name  |       email        |          created_at
----+-------+--------------------+-------------------------------
  1 | Alice | alice@example.com  | 2026-05-21 10:00:00.000000+00
  2 | Bob   | bob@example.com    | 2026-05-21 10:00:01.000000+00
(2 rows)

 id | customer_id | amount | status    |          created_at
----+-------------+--------+-----------+-------------------------------
  1 |           1 |  99.99 | completed | 2026-05-21 10:00:00.000000+00
  2 |           2 | 149.50 | pending   | 2026-05-21 10:00:01.000000+00
(2 rows)
```

### Check replication slot on Publisher

```sql
-- Connect to publisher as master
psql -h 172.18.0.11 -U master -d cdc_db

SELECT slot_name, plugin, slot_type, database, active, restart_lsn, confirmed_flush_lsn
FROM   pg_replication_slots;
```

Expected output:
```
   slot_name   |  plugin  | slot_type | database | active | restart_lsn | confirmed_flush_lsn
---------------+----------+-----------+----------+--------+-------------+---------------------
 debezium_slot | pgoutput | logical   | cdc_db   | t      | 0/1234ABCD  | 0/1234ABCD
(1 row)
```

### Check replication lag on Publisher

```sql
SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM   pg_replication_slots
WHERE  slot_type = 'logical';
```

Expected output:
```
   slot_name   |   lag
---------------+---------
 debezium_slot | 0 bytes
(1 row)
```

---

## Step 11 — On Publisher - By DBA - Add cron job to run `repl_slot_manager.py` every 30 minutes.

The Python script `repl_slot_manager.py` manages the lifecycle of logical replication slots exclusively
through the Patroni DCS config (`patronictl edit-config`). Patroni itself creates or drops physical slots
on the leader node. `dba.replication_slot_config` is the sole source of truth. All events and actions are
audited in `dba.replication_slot_config_log` — no log files are used.

### Algorithm

1. Run the cron job as the `postgres` user.
2. Accept the following optional arguments:
   - `--patronictl-config`      — path to `patroni.yml` (default: `/etc/patroni/patroni.yml`)
   - `--db-log-days-to-keep`   — retention period in days for `dba.replication_slot_config_log` (default: `15`)
   - `--wal-level-buffer-hours` — buffer window in hours before Scenario 01 reverts `wal_level` (default: `2`)
3. Read the Patroni cluster name (`scope`) from `patroni.yml`.
4. **Guard — leader check**: run `patronictl list` and compare the current hostname against the TSV output.
   - If the current node is **not** the `Leader`, print and exit immediately.
   - Only the cluster leader proceeds. Because only the leader node is writable, the `hostname` column in
     the audit table will always reflect the current Patroni leader.
5. **Purge old audit rows**: delete rows from `dba.replication_slot_config_log` where
   `logged_at < now() - interval '<db-log-days-to-keep> days'`.
6. Fetch the live `wal_level` from PostgreSQL: `SHOW wal_level;` → `WAL_LEVEL_PG` event logged.
7. Fetch the Patroni DCS config via `patronictl show-config`:
   - Parse `wal_level` → `wal_level_patroni` → `WAL_LEVEL_PATRONI` event logged.
   - Parse the `slots:` section → `patroni_slots` (logical slots only; physical slots such as
     `standby_cluster_slot` are skipped) → `SLOT_PATRONI` event logged per slot.
8. Read desired slot state from `dba.replication_slot_config` (in the `postgres` database):
   - Rows with `desired = true`  → `desired_slots`  → `SLOT_CONFIG_DESIRED` event per slot.
   - Rows with `desired = false` → `undesired_slots` → `SLOT_CONFIG_UNDESIRED` event per slot.
   - All slot names, plugins, and databases are normalised to lowercase.
9. **Evaluate scenario** based on `wal_level` (live) and `desired_slots` count:

   **Scenario 01** — `wal_level = LOGICAL` AND `desired_slots = 0`

   Before acting, evaluate two independent **buffer windows** in priority order:

   **Buffer A — `wal_level` just became LOGICAL** (`wal_in_buffer`, checked first):
   - Query `dba.replication_slot_config_log` for the earliest `WAL_LEVEL_PG = logical` observation
     newer than the most recent `WAL_LEVEL_PG != logical` observation. This gives the timestamp when
     `wal_level` first became `LOGICAL` in the current streak (`wal_logical_since`).
   - If `wal_logical_since` is within `wal-level-buffer-hours`:
     - Trigger **`Scenario 01 (BUFFERED)`** → `SCENARIO` event logged.
     - **Skip everything** — no slot removal, no `wal_level` revert.
     - Assumption: customer just enabled logical replication and has not yet added slots.

   **Buffer B — a slot was recently removed** (`slot_in_buffer`, checked only if Buffer A does not apply):
   - Query `dba.replication_slot_config_log` for the most recent `SLOT_REMOVED` event with
     `scenario = 'Scenario 03'` (i.e., removed because customer set `desired = false` or deleted the row).
   - If that timestamp is within `wal-level-buffer-hours`:
     - Trigger **`Scenario 01 (SLOT_REMOVED_BUFFER)`** → `SLOT_REMOVED` + `SCENARIO` events logged.
     - **Remove all logical slots from Patroni DCS config immediately** (`--set "slots={}"`) →
       `SLOT_REMOVED` event per slot.
     - **Hold the `wal_level` revert** — do NOT change `wal_level` in Patroni or PostgreSQL.
     - Assumption: customer removed the last slot but may be adding a replacement shortly.

   **No buffer applies** (both windows expired, or no prior observations found):
   - Trigger **`Scenario 01`** → `SCENARIO` event logged.
   - Run `patronictl edit-config --pg "wal_level=replica"` → `WAL_LEVEL_REVERTED` event.
   - If any logical slots still exist in the Patroni DCS config, remove them all with
     `--set "slots={}"` → `SLOT_REMOVED` event per slot.
   - Log result: `Scenario 01: wal_level reverted to replica. Patroni logical slots cleared.`

   **Scenario 03** — everything else (`wal_level ≠ LOGICAL`, or `desired_slots > 0`)
   - **CDC parameter sync**: if `wal_level_patroni ≠ LOGICAL`, apply the full set of required CDC
     parameters in one `patronictl edit-config` call → `WAL_LEVEL_SET_LOGICAL` event:
     ```
     postgresql.parameters.wal_level             = logical
     postgresql.parameters.wal_log_hints         = on
     postgresql.parameters.max_replication_slots = 10
     postgresql.parameters.max_wal_senders       = 10
     postgresql.use_pg_rewind = true
     postgresql.use_slots     = true
     ```
   - **Add missing slots**: for each entry in `desired_slots`, if the slot name is not already present
     in `patroni_slots` (case-insensitive), add it via `patronictl edit-config` → `SLOT_ADDED` event:
     ```
     slots.<slot_name>.type     = logical
     slots.<slot_name>.database = <database>
     slots.<slot_name>.plugin   = <plugin>
     ```
   - **Remove stale slots**: for each slot in `patroni_slots`, if its name is not in `desired_slots`
     (covers `desired = false` rows and rows deleted from the config table), remove it from the Patroni
     DCS config via `patronictl edit-config --set "slots.<slot_name>="` → `SLOT_REMOVED` event.
   - If no adds or removals were needed, log that the config is already in sync.

10. Log final `SUMMARY` event with scenario, wal_level, config counts, and patroni change counts.

### Python script repl_slot_manager.py

See [`repl_slot_manager.py`](roles/pg_cluster/files/repl_slot_manager.py)

```bash
# Run as postgres user
python3 repl_slot_manager.py \
  --patronictl-config=/etc/patroni/patroni.yml \
  --db-log-days-to-keep=15 \
  --wal-level-buffer-hours=2

# Normal cron run — buffer windows active
python3 repl_slot_manager.py

# DBA forcing immediate revert right now (e.g. emergency cleanup)
python3 repl_slot_manager.py --skip-buffer

# Make config changes AND restart immediately
python3 repl_slot_manager.py --skip-buffer --force-restart

# Force + silent (no console/file noise, just DB table audit)
python3 repl_slot_manager.py --skip-buffer --no-log-to-console --no-log-to-file
```

### Cron job (every 30 minutes, as postgres user)

```
*/30 * * * * postgres python3 /var/lib/postgresql/18/scripts/repl_slot_manager.py \
  --patronictl-config=/etc/patroni/patroni.yml \
  --db-log-days-to-keep=15 \
  --wal-level-buffer-hours=2
```

### Deploy through Ansible
```
cd ~/Documents/Github/Personal/PostgreSQL-Learning/playbook-install-pg-cluster-docker-etcd

ansible-playbook -i hosts.yml playbook-install-primary-cluster.yml \
  --vault-password-file=vault-pass --tags repl_slot_manager \
   2>&1 | tee run_logs/playbook-install-primary-cluster--repl_slot_manager.yml.log
```

---

## Full Cleanup (Remove Everything)

*Actor: Customer via psql using `master` or `replication_admin`*

```sql
-- *** On Subscriber — connect as replication_admin ***
psql -h 172.18.0.21 -U replication_admin -d cdc_db

-- 1. Drop subscription (also drops debezium_slot on publisher automatically)
DROP SUBSCRIPTION IF EXISTS cdc_subscription;

-- *** On Publisher — connect as replication_admin ***
psql -h 172.18.0.11 -U replication_admin -d cdc_db

-- 2. Drop publication on publisher
DROP PUBLICATION IF EXISTS cdc_publication;

-- 3. Drop replication slot if it still exists (e.g. subscription was dropped without cascade)
SELECT pg_drop_replication_slot(slot_name)
FROM   pg_replication_slots
WHERE  slot_name = 'debezium_slot';

-- *** On Publisher — connect as master ***
psql -h 172.18.0.11 -U master -d postgres

update dba.replication_slot_config set desired = false where slot_name = 'debezium_slot';



```

---

## Quick Reference

| Object              | Actor               | Create                                  | Verify                    | Update                     | Remove                           |
|---------------------|---------------------|-----------------------------------------|---------------------------|----------------------------|----------------------------------|
| Database            | `master`            | `CREATE DATABASE`                       | `\l dbname`               | —                          | `DROP DATABASE`                  |
| Roles               | `master`            | `CREATE ROLE`                           | `\du`                     | `ALTER ROLE`               | `DROP ROLE`                      |
| pg_hba entry        | DBA (patronictl)    | `patronictl edit-config`                | `pg_hba_file_rules`       | `patronictl edit-config`   | `patronictl edit-config`         |
| Publication         | `replication_admin` | `CREATE PUBLICATION`                    | `pg_publication`          | `ALTER PUBLICATION`        | `DROP PUBLICATION`               |
| Replication slot    | `replication_admin` | `pg_create_logical_replication_slot()`  | `pg_replication_slots`    | —                          | `pg_drop_replication_slot()`     |
| Subscription        | `replication_admin` | `CREATE SUBSCRIPTION`                   | `pg_subscription`         | `ALTER SUBSCRIPTION`       | `DROP SUBSCRIPTION`              |
| REPLICA IDENTITY    | `master`            | `ALTER TABLE ... REPLICA IDENTITY FULL` | `pg_class.relreplident`   | —                          | `ALTER TABLE ... IDENTITY DEFAULT` |
| Table ownership     | `master`            | `ALTER TABLE ... OWNER TO`              | `\dt+`                    | `ALTER TABLE ... OWNER TO` | revert to original owner         |

---

## Troubleshooting

### 0. Check Replication Status

```sql
-- On Publisher
select usename, application_name, client_addr, backend_start, state, sync_state, sync_priority, sent_lsn, replay_lsn, replay_lag, reply_time 
from pg_stat_replication;

select slot_name, plugin, slot_type, database, temporary, active, wal_status, inactive_since, conflicting, failover, synced
from pg_replication_slots;

select slot_name, plugin, database from pg_replication_slots where slot_type = 'logical';
```

---

### 1. Check subscription sync state

Run on **subscriber** as `master`:

```sql
-- srsubstate values:
-- i = initialize, d = data copy in progress, f = finished copy, s = synchronized, r = ready, e = error
SELECT srsubid, srrelid::regclass AS table_name, srsubstate, srsublsn
FROM   pg_subscription_rel;
```

| `srsubstate` | Meaning | Action |
|---|---|---|
| `d` with PID in pg_stat_subscription | Initial sync actively running | Wait |
| `d` with no PID | Sync worker crashed / stuck | Check logs, refresh subscription |
| `r` | Normal replication streaming | No action needed |
| `e` | Error | Check `pg_stat_subscription` and logs |

---

### 2. Check if subscription worker is running

Run on **subscriber**:

```sql
\x
SELECT * FROM pg_stat_subscription;
```

- `pid` present → worker is active
- `pid` NULL / no row → worker not running → subscription may be disabled or crashed

---

### 3. Check if replication slot is active on Publisher

Run on **publisher** as `master`:

```sql
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM   pg_replication_slots
WHERE  slot_name = 'debezium_slot';
```

| `active` | Meaning |
|---|---|
| `t` | Subscriber is connected and consuming WAL |
| `f` | Subscriber is NOT connected — sync is stuck or subscription is disabled |

---

### 4. Check PostgreSQL logs on Subscriber

```bash
docker logs postgres --tail 50
```

Look for errors like:
- `could not connect to the publisher` → network/pg_hba issue
- `permission denied` → missing `GRANT CREATE ON DATABASE` on subscriber
- `replication slot "debezium_slot" does not exist` → slot was dropped on publisher
- `role "replication_admin" cannot SET ROLE to "<owner>"` → tables on subscriber not owned by `replication_group` (see fix below)

---

### 5. Refresh subscription if tables are stuck in `d` state

Run on **subscriber** as `replication_admin`:

```sql
ALTER SUBSCRIPTION cdc_subscription REFRESH PUBLICATION;
```

---

### 6. Disable and re-enable subscription to restart workers

Run on **subscriber** as `replication_admin`:

```sql
ALTER SUBSCRIPTION cdc_subscription DISABLE;
ALTER SUBSCRIPTION cdc_subscription ENABLE;
```

---

### 7. tablesync worker crash — `cannot SET ROLE to "<owner>"`

**Symptom:** `docker logs postgres` shows:
```
ERROR: role "replication_admin" cannot SET ROLE to "master"
background worker "logical replication tablesync worker" exited with exit code 1
```

**Cause:** PostgreSQL 16+ tablesync workers do `SET ROLE` to the table owner before writing the initial data copy. If tables on the subscriber are owned by `master` (not `replication_group`), `replication_admin` cannot impersonate `master`.

**Fix — on subscriber as `master`:**

```sql
psql -h localhost -U master -d cdc_db

ALTER TABLE public.customers OWNER TO replication_group;
ALTER TABLE public.orders    OWNER TO replication_group;
```

Tablesync workers restart automatically within ~5 seconds. Verify:

```sql
-- Should show tablesync worker rows
SELECT worker_type, pid, relid::regclass AS table_name FROM pg_stat_subscription;

-- srsubstate should move from 'd' → 'r'
SELECT srrelid::regclass AS table_name, srsubstate FROM pg_subscription_rel;
```

---

### 8. Common errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `permission denied for database cdc_db` | `replication_group` missing `CREATE` on subscriber's `cdc_db` | `GRANT CREATE ON DATABASE cdc_db TO replication_group;` on subscriber |
| `cannot SET ROLE to "<owner>"` | Tables on subscriber not owned by `replication_group` | `ALTER TABLE ... OWNER TO replication_group;` on subscriber (see §7 above) |
| `replication slot does not exist` | Slot was dropped or never created | Re-create slot on publisher: `SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput');` |
| `publication does not exist` | Publication missing on publisher | Re-run Step 7 |
| `srsubstate stuck at d`, no PID | Sync worker crashed | Check logs, fix root cause, then disable/enable subscription |
| `active = f` on slot | Subscriber not connecting to publisher | Check pg_hba on publisher, network connectivity |
| `could not connect to publisher` | Wrong host/port in CONNECTION string, or pg_hba blocking | Verify `host=` IP, check `pg_hba_file_rules` on publisher |
