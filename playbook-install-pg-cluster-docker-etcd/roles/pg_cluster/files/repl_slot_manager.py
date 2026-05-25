#!/usr/bin/env python3
"""
Manages logical replication slots based on dba.replication_slot_config and syncs Patroni DCS config.
Run as postgres user.
Usage: python3 repl_slot_manager.py [--patronictl-config=] [--db-log-days-to-keep=]
                                     [--wal-level-buffer-hours=] [--logs-path=] [--logs-days-to-keep=]
                                     [--log-to-console] [--no-log-to-console]
                                     [--log-to-file]    [--no-log-to-file]
"""
import argparse, glob, os, re, socket, subprocess, sys, uuid
from datetime import datetime, timedelta
from pathlib import Path

# Module-level flags set by setup_logging() before anything else runs.
# Log destinations: console and file apply to all hosts; log table only on the leader (via DL()).
_log_file        = None   # path to the current run's log file; None until setup_logging() is called
_log_to_console  = True   # write entries to stdout
_log_to_file     = True   # write entries to the local log file

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--patronictl-config",      default="/etc/patroni/patroni.yml")
    p.add_argument("--db-log-days-to-keep",    type=int, default=15)
    # Ajay Dwivedi - TS-XXXXX - Buffer window: skip Scenario 01 revert if wal_level became LOGICAL recently.
    p.add_argument("--wal-level-buffer-hours", type=int, default=2)
    p.add_argument("--logs-path",              default=str(Path.home() / "logs"))
    p.add_argument("--logs-days-to-keep",      type=int, default=7)
    # Log destination toggles: use --no-log-to-console / --no-log-to-file to disable each sink.
    p.add_argument("--log-to-console", default=True,  action=argparse.BooleanOptionalAction)
    p.add_argument("--log-to-file",    default=True,  action=argparse.BooleanOptionalAction)
    return p.parse_args()

def setup_logging(logs_path, days_to_keep, log_to_console, log_to_file):
    """Set log destination flags and, when log_to_file=True, create the log dir, open a new
    timestamped log file, and remove files older than days_to_keep.
    Called before the leader check so every host (leader and replica) is covered.
    """
    global _log_file, _log_to_console, _log_to_file
    _log_to_console = log_to_console
    _log_to_file    = log_to_file
    if log_to_file:
        os.makedirs(logs_path, exist_ok=True)
        ts = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        _log_file = os.path.join(logs_path, f"repl_slot_manager_{ts}.log")
        cutoff = datetime.now() - timedelta(days=days_to_keep)
        for old in glob.glob(os.path.join(logs_path, "repl_slot_manager_*.log")):
            try:
                m = re.search(r'(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})', old)
                if m and datetime.strptime(m.group(1), "%Y-%m-%d_%H-%M-%S") < cutoff:
                    os.remove(old)
            except Exception:
                pass

def plog(level, message):
    """Route a timestamped log entry to the enabled destinations (console and/or file).
    Log table routing is handled separately by DL() and only runs on the cluster leader.
    """
    entry = f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} [{level}]: {message}"
    if _log_to_console:
        print(entry)
    if _log_to_file and _log_file:
        try:
            with open(_log_file, "a") as f:
                f.write(entry + "\n")
        except Exception:
            pass

def run(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.stderr:
        plog("INFO", f"stderr: {result.stderr.strip()}")
    return result.stdout.strip(), result.returncode

def get_cluster_name(config_file):
    with open(config_file) as f:
        for line in f:
            m = re.match(r'^scope:\s*["\']?([^"\']+)["\']?', line)
            if m:
                return m.group(1).strip()
    raise ValueError("Could not find 'scope' in patroni config.")

def is_leader(config_file, cluster_name):
    out, _ = run(f"patronictl -c {config_file} list {cluster_name} --format=tsv")
    hostname = socket.gethostname()
    for line in out.splitlines():
        parts = line.split("\t")
        # TSV columns: Cluster(0) Member(1) Host(2) Role(3) ...
        if len(parts) >= 4 and parts[1].strip() == hostname and parts[3].strip() == "Leader":
            return True
    return False

def get_wal_level():
    out, _ = run("psql -U postgres -tAc 'SHOW wal_level;'")
    return out.strip().upper()

def get_patroni_config(config_file, cluster_name):
    out, _ = run(f"patronictl -c {config_file} show-config {cluster_name}")
    return out

def parse_patroni_wal_level(patroni_config):
    m = re.search(r'wal_level:\s*["\']?(\w+)["\']?', patroni_config)
    return m.group(1).upper() if m else "REPLICA"

def parse_patroni_slots(patroni_config):
    """Parse Patroni config slots section. Returns only logical slots (skips physical)."""
    slots = {}
    in_slots = False
    current_slot = None
    for line in patroni_config.splitlines():
        if re.match(r'^slots:', line):
            in_slots = True; continue
        if in_slots:
            if re.match(r'^[^ ]', line):
                in_slots = False; current_slot = None; continue
            m = re.match(r'^  (\S+):', line)
            if m:
                current_slot = m.group(1)
                slots[current_slot] = {"type": "logical"}  # default to logical
                continue
            m2 = re.match(r'^\s{4}(\w+):\s*["\']?(.+?)["\']?\s*$', line)
            if m2 and current_slot:
                slots[current_slot][m2.group(1)] = m2.group(2)
    # Filter: only return logical slots; physical slots (e.g. standby_cluster_slot) are excluded
    return {name: props for name, props in slots.items() if props.get("type", "logical") == "logical"}

def get_wal_level_became_logical_time():
    """Returns the datetime when the current consecutive WAL_LEVEL_PG=LOGICAL streak started.
    Finds the earliest LOGICAL observation newer than the most recent non-LOGICAL observation.
    Used to implement a buffer window check in Scenario 01.
    Returns None if no LOGICAL streak is found in the log table.
    Ajay Dwivedi - TS-XXXXX - Buffer window: detect when wal_level first became LOGICAL.
    """
    query = (
        "SELECT to_char(min(logged_at), 'YYYY-MM-DD HH24:MI:SS') "
        "FROM dba.replication_slot_config_log "
        "WHERE event_type = 'WAL_LEVEL_PG' AND lower(wal_level) = 'logical' "
        "AND logged_at > ("
        "  SELECT COALESCE(max(logged_at), '1970-01-01'::timestamptz) "
        "  FROM dba.replication_slot_config_log "
        "  WHERE event_type = 'WAL_LEVEL_PG' AND lower(wal_level) != 'logical'"
        ");"
    )
    out, rc = run(f"psql -U postgres -d postgres -tAc \"{query}\"")
    if rc == 0 and out.strip() and out.strip().lower() not in ('', 'null'):
        try:
            return datetime.strptime(out.strip(), "%Y-%m-%d %H:%M:%S")
        except Exception:
            return None
    return None

def get_last_slot_removed_time():
    """Returns the datetime of the most recent SLOT_REMOVED event logged under Scenario 03.
    Scenario 03 removes a slot from Patroni DCS when the customer sets desired=false in the config table.
    Used to detect if a slot was recently removed — the customer may be adding a replacement slot.
    Returns None if no such event is found in the log table.
    Ajay Dwivedi - TS-XXXXX - Buffer window: detect when a slot was last removed by customer action.
    """
    query = (
        "SELECT to_char(max(logged_at), 'YYYY-MM-DD HH24:MI:SS') "
        "FROM dba.replication_slot_config_log "
        "WHERE event_type = 'SLOT_REMOVED' AND scenario = 'Scenario 03';"
    )
    out, rc = run(f"psql -U postgres -d postgres -tAc \"{query}\"")
    if rc == 0 and out.strip() and out.strip().lower() not in ('', 'null'):
        try:
            return datetime.strptime(out.strip(), "%Y-%m-%d %H:%M:%S")
        except Exception:
            return None
    return None

def db_log(run_id, hostname, cluster_name, event_type, message,
           slot_name=None, plugin=None, database=None, wal_level=None,
           desired=None, scenario=None):
    """Insert one audit row into dba.replication_slot_config_log.
    SQL is fed to psql via stdin (no shell) so that $msg$ dollar-quote tags are never
    expanded by bash as shell variables. Failures print a warning; the script never aborts.
    """
    def _sql_str(v): return f"'{v}'" if v is not None else "NULL"
    def _sql_bool(v): return ("true" if v else "false") if v is not None else "NULL"
    sql = (
        "INSERT INTO dba.replication_slot_config_log "
        "(run_id, hostname, cluster_name, event_type, slot_name, plugin, database, "
        " wal_level, desired, scenario, message) VALUES ("
        f"'{run_id}', '{hostname}', '{cluster_name}', '{event_type}', "
        f"{_sql_str(slot_name)}, {_sql_str(plugin)}, {_sql_str(database)}, "
        f"{_sql_str(wal_level)}, {_sql_bool(desired)}, {_sql_str(scenario)}, "
        f"$msg${message}$msg$);"
    )
    # Pass SQL via stdin so the shell never touches the $msg$ dollar-quote delimiters.
    result = subprocess.run(
        ["psql", "-U", "postgres", "-d", "postgres"],
        input=sql, capture_output=True, text=True
    )
    if result.returncode != 0:
        plog("INFO", f"WARNING: db_log insert failed for event_type={event_type}. "
                     f"stderr: {result.stderr.strip()}")

def get_config_table_slots():
    """Read dba.replication_slot_config from postgres database.
    Returns (desired_slots, undesired_slots) as lists of dicts with keys: slot_name, plugin, database.
    slot_name/plugin/database are returned lowercase (citext columns).
    Ajay Dwivedi - TS-XXXXX - Config-table driven slot management
    """
    query = ("SELECT lower(slot_name), lower(plugin), lower(database), desired::text, "
             "to_char(created_at,'YYYY-MM-DD HH24:MI:SS'), to_char(updated_at,'YYYY-MM-DD HH24:MI:SS') "
             "FROM dba.replication_slot_config ORDER BY slot_name;")
    out, _ = run(f"psql -U postgres -d postgres -tAF '|' -c \"{query}\"")
    desired, undesired = [], []
    for line in out.splitlines():
        parts = line.strip().split("|")
        if len(parts) == 6 and parts[0]:
            entry = {"slot_name": parts[0], "plugin": parts[1], "database": parts[2],
                     "desired": parts[3] == "true", "created_at": parts[4], "updated_at": parts[5]}
            (desired if entry["desired"] else undesired).append(entry)
    return desired, undesired

def patronictl_edit(config_file, cluster_name, args_str):
    cmd = f"patronictl -c {config_file} edit-config {cluster_name} --force {args_str}"
    _, rc = run(cmd)
    return rc == 0

def main():
    import traceback
    args = parse_args()

    # Set up log destinations on every host regardless of role.
    # Console and file apply to all hosts; log table (DL) applies only after leader check passes.
    setup_logging(args.logs_path, args.logs_days_to_keep, args.log_to_console, args.log_to_file)

    # Unique ID shared by every db_log row written during this run.
    run_id = str(uuid.uuid4())
    hostname = socket.gethostname()
    # cluster_name resolved after config file is read; placeholder until then.
    cluster_name = "unknown"

    def DL(event_type, message, **kwargs):
        """Write one row to dba.replication_slot_config_log (best-effort; never raises)."""
        try:
            db_log(run_id, hostname, cluster_name, event_type, message, **kwargs)
        except Exception as ex:
            plog("INFO", f"WARNING: db_log raised {ex} for event_type={event_type}.")

    try:
        plog("INFO", f"Script started. config={args.patronictl_config}, "
                     f"db_log_days_to_keep={args.db_log_days_to_keep}, run_id={run_id}")

        cluster_name = get_cluster_name(args.patronictl_config)
        plog("INFO", f"Patroni cluster name: {cluster_name}")

        plog("INFO", "Checking if current node is Patroni cluster leader...")
        if not is_leader(args.patronictl_config, cluster_name):
            plog("INFO", "Current node is not the cluster leader. Exiting."); sys.exit(0)
        plog("INFO", "Current node is the cluster leader. Proceeding.")
        DL("START", f"Script run started. [config={args.patronictl_config}, "
                    f"db_log_days_to_keep={args.db_log_days_to_keep}, "
                    f"wal_level_buffer_hours={args.wal_level_buffer_hours}, run_id={run_id}]")

        # --- Purge old log entries from dba.replication_slot_config_log ---
        plog("INFO", f"Purging dba.replication_slot_config_log entries older than {args.db_log_days_to_keep} days...")
        purge_sql = f"DELETE FROM dba.replication_slot_config_log WHERE logged_at < now() - interval '{args.db_log_days_to_keep} days';"
        _, purge_rc = run(f"psql -U postgres -d postgres -c \"{purge_sql}\"")
        if purge_rc == 0:
            plog("INFO", "Purge of old log entries completed.")
        else:
            plog("INFO", "WARNING: Purge of old log entries failed.")

        # --- Observe: wal_level from PostgreSQL ---
        plog("INFO", "Fetching wal_level from PostgreSQL...")
        wal_level = get_wal_level()
        plog("RESULT", f"Current wal_level is {wal_level}.")
        DL("WAL_LEVEL_PG", f"Current wal_level is {wal_level}.", wal_level=wal_level)

        # --- Observe: Patroni DCS config ---
        plog("INFO", "Fetching Patroni config via patronictl show-config...")
        patroni_config = get_patroni_config(args.patronictl_config, cluster_name)
        wal_level_patroni = parse_patroni_wal_level(patroni_config)
        # parse_patroni_slots returns only logical slots (physical slots like standby_cluster_slot are excluded)
        patroni_slots = parse_patroni_slots(patroni_config)
        plog("RESULT", f"Patroni config wal_level is {wal_level_patroni}.")
        DL("WAL_LEVEL_PATRONI", f"Patroni config wal_level is {wal_level_patroni}.", wal_level=wal_level_patroni)
        if not patroni_slots:
            plog("INFO", "No logical replication slots found in Patroni config.")
        for sn, props in patroni_slots.items():
            msg = f"Patroni config logical slot found. [Slot Name: {sn}, Plugin: {props.get('plugin','')}, Database: {props.get('database','')}]"
            plog("RESULT", msg)
            DL("SLOT_PATRONI", msg, slot_name=sn, plugin=props.get("plugin"), database=props.get("database"))
        plog("RESULT", f"Total logical slots in Patroni config: {len(patroni_slots)}")

        # --- Observe: dba.replication_slot_config ---
        # Ajay Dwivedi - TS-XXXXX - Config-table driven slot management: read desired state.
        plog("INFO", "Fetching desired slot configuration from dba.replication_slot_config table...")
        desired_slots, undesired_slots = get_config_table_slots()
        for s in desired_slots:
            msg = f"Config slot (desired=true). [Slot Name: {s['slot_name']}, Plugin: {s['plugin']}, Database: {s['database']}, created_at: {s['created_at']}, updated_at: {s['updated_at']}]"
            plog("RESULT", msg)
            DL("SLOT_CONFIG_DESIRED", msg, slot_name=s["slot_name"], plugin=s["plugin"], database=s["database"], desired=True)
        for s in undesired_slots:
            msg = f"Config slot (desired=false). [Slot Name: {s['slot_name']}, Plugin: {s['plugin']}, Database: {s['database']}, updated_at: {s['updated_at']}]"
            plog("RESULT", msg)
            DL("SLOT_CONFIG_UNDESIRED", msg, slot_name=s["slot_name"], plugin=s["plugin"], database=s["database"], desired=False)
        if not desired_slots and not undesired_slots:
            plog("INFO", "No slots found in dba.replication_slot_config.")
        plog("RESULT", f"Config table: desired_slots={len(desired_slots)}, undesired_slots={len(undesired_slots)}.")

        # --- Decide and act ---
        # Slot lifecycle is managed exclusively via Patroni DCS config (patronictl edit-config).
        # Patroni itself creates/drops physical slots on the leader node based on DCS config.
        slots_added = 0; slots_removed = 0; scenario_triggered = "None"
        desired_slot_names_set = {s["slot_name"] for s in desired_slots}

        plog("INFO", f"Evaluating scenario: wal_level={wal_level}, config_desired={len(desired_slots)}, patroni_logical_slots={len(patroni_slots)}")

        if wal_level == "LOGICAL" and len(desired_slots) == 0:
            # Ajay Dwivedi - TS-XXXXX - Buffer window: two independent guards before reverting wal_level.
            wal_logical_since = get_wal_level_became_logical_time()
            last_slot_removed = get_last_slot_removed_time()
            buffer_seconds = args.wal_level_buffer_hours * 3600
            now = datetime.now()
            wal_in_buffer  = (wal_logical_since is not None and
                              (now - wal_logical_since).total_seconds() < buffer_seconds)
            slot_in_buffer = (last_slot_removed is not None and
                              (now - last_slot_removed).total_seconds() < buffer_seconds)

            if wal_in_buffer:
                # wal_level just became LOGICAL but no slots added yet — skip everything.
                # Customer is in the process of adding their first slot to the config table.
                scenario_triggered = "Scenario 01 (BUFFERED)"
                msg = (f"Scenario 01 condition met (wal_level=LOGICAL, no desired slots) but SKIPPED: "
                       f"wal_level became LOGICAL at {wal_logical_since} "
                       f"(within {args.wal_level_buffer_hours}h buffer window). "
                       f"Assuming customer is in process of adding slots.")
                plog("INFO", msg)
                DL("SCENARIO", msg, scenario=scenario_triggered)

            elif slot_in_buffer:
                # A slot was recently removed — customer may be adding a replacement slot.
                # Remove Patroni slots immediately but hold off reverting wal_level.
                scenario_triggered = "Scenario 01 (SLOT_REMOVED_BUFFER)"
                if len(patroni_slots) > 0:
                    plog("INFO", f"Scenario 01 (SLOT_REMOVED_BUFFER): Removing {len(patroni_slots)} logical slot(s) from Patroni config immediately...")
                    patronictl_edit(args.patronictl_config, cluster_name, "--set 'slots={}'")
                    slots_removed = len(patroni_slots)
                    for sn in patroni_slots:
                        DL("SLOT_REMOVED", f"Slot '{sn}' removed from Patroni DCS config immediately (slot-removed buffer: wal_level revert deferred).", slot_name=sn, scenario=scenario_triggered)
                else:
                    plog("INFO", "Scenario 01 (SLOT_REMOVED_BUFFER): No logical slots in Patroni config to remove.")
                msg = (f"Scenario 01 condition met but wal_level revert DEFERRED: "
                       f"slot last removed at {last_slot_removed} "
                       f"(within {args.wal_level_buffer_hours}h buffer window). "
                       f"Patroni slots cleared immediately. Waiting before reverting wal_level to replica.")
                plog("INFO", msg)
                DL("SCENARIO", msg, scenario=scenario_triggered)

            else:
                # Buffer window expired — full revert: wal_level back to replica and clear Patroni slots.
                scenario_triggered = "Scenario 01"
                DL("SCENARIO", "Scenario 01 triggered: wal_level=LOGICAL and no desired slots in config table. Reverting.", scenario=scenario_triggered)
                plog("INFO", "Scenario 01 triggered: wal_level=LOGICAL and no desired slots in config table. Reverting.")
                plog("INFO", "Scenario 01: Reverting wal_level to replica in Patroni config...")
                patronictl_edit(args.patronictl_config, cluster_name, '--pg "wal_level=replica"')
                DL("WAL_LEVEL_REVERTED", "wal_level reverted to replica in Patroni DCS config.", wal_level="replica", scenario=scenario_triggered)
                if len(patroni_slots) > 0:
                    plog("INFO", f"Scenario 01: Removing {len(patroni_slots)} logical slot(s) from Patroni config...")
                    patronictl_edit(args.patronictl_config, cluster_name, "--set 'slots={}'")
                    slots_removed = len(patroni_slots)
                    for sn in patroni_slots:
                        DL("SLOT_REMOVED", f"Slot '{sn}' removed from Patroni DCS config (Scenario 01 revert).", slot_name=sn, scenario=scenario_triggered)
                else:
                    plog("INFO", "Scenario 01: No logical slots in Patroni config to remove.")
                plog("RESULT", "Scenario 01: wal_level reverted to replica. Patroni logical slots cleared.")
        else:
            if wal_level != "LOGICAL":
                plog("INFO", f"Condition not met for Scenario 01: wal_level={wal_level} (not LOGICAL).")
            else:
                plog("INFO", f"Condition not met for Scenario 01: {len(desired_slots)} desired slot(s) in config table (wal_level=LOGICAL).")
            scenario_triggered = "Scenario 03"
            DL("SCENARIO", "Scenario 03 triggered: Syncing config table desired slots with Patroni DCS config.", scenario=scenario_triggered)
            plog("INFO", "Scenario 03 triggered: Syncing config table desired slots with Patroni config.")
            # When setting wal_level=logical, always apply the full set of required CDC parameters.
            if wal_level_patroni != "LOGICAL":
                plog("INFO", f"Scenario 03: Patroni config wal_level is {wal_level_patroni}. Updating to LOGICAL with all required parameters...")
                patronictl_edit(args.patronictl_config, cluster_name,
                    '--set "postgresql.parameters.wal_level=logical"'
                    ' --set "postgresql.parameters.wal_log_hints=on"'
                    ' --set "postgresql.parameters.max_replication_slots=10"'
                    ' --set "postgresql.parameters.max_wal_senders=10"'
                    ' --set "postgresql.use_pg_rewind=true"'
                    ' --set "postgresql.use_slots=true"')
                plog("RESULT", "Scenario 03: Patroni config wal_level set to LOGICAL with all required CDC parameters.")
                DL("WAL_LEVEL_SET_LOGICAL", "Full CDC parameters applied to Patroni DCS config (wal_level=logical, wal_log_hints=on, max_replication_slots=10, max_wal_senders=10, use_pg_rewind=true, use_slots=true).", wal_level="logical", scenario=scenario_triggered)
            else:
                plog("INFO", "Scenario 03: Patroni config wal_level is already LOGICAL. No wal_level update needed.")
            # Add desired config slots to Patroni config if missing (case-insensitive comparison).
            patroni_slot_names_lower = {k.lower() for k in patroni_slots}
            for s in desired_slots:
                sn = s["slot_name"]
                if sn.lower() not in patroni_slot_names_lower:
                    plog("INFO", f"Scenario 03: Slot '{sn}' missing from Patroni config. Adding...")
                    patronictl_edit(args.patronictl_config, cluster_name,
                        f'--set "slots.{sn}.type=logical" --set "slots.{sn}.database={s["database"]}" --set "slots.{sn}.plugin={s["plugin"]}"')
                    plog("RESULT", f"Scenario 03: Slot '{sn}' added to Patroni config.")
                    DL("SLOT_ADDED", f"Slot '{sn}' added to Patroni DCS config.", slot_name=sn, plugin=s["plugin"], database=s["database"], desired=True, scenario=scenario_triggered)
                    slots_added += 1
                else:
                    plog("INFO", f"Scenario 03: Slot '{sn}' already in Patroni config. No action required.")
            # Remove Patroni logical slots not in desired config (undesired or row deleted from config table).
            for patroni_slot in list(patroni_slots.keys()):
                if patroni_slot.lower() not in desired_slot_names_set:
                    plog("INFO", f"Scenario 03: Patroni logical slot '{patroni_slot}' not in desired config. Removing from Patroni...")
                    patronictl_edit(args.patronictl_config, cluster_name, f'--set "slots.{patroni_slot}="')
                    plog("RESULT", f"Scenario 03: Logical slot '{patroni_slot}' removed from Patroni config.")
                    DL("SLOT_REMOVED", f"Slot '{patroni_slot}' removed from Patroni DCS config (not in desired config).", slot_name=patroni_slot, scenario=scenario_triggered)
                    slots_removed += 1
                else:
                    plog("INFO", f"Scenario 03: Patroni logical slot '{patroni_slot}' exists in desired config. No action required.")
            if slots_added == 0 and slots_removed == 0:
                plog("INFO", "Scenario 03: Config table desired slots and Patroni config are already in sync. No changes made.")

        scenario_summaries = {
            "Scenario 01": "wal_level=LOGICAL with no desired slots -> reverted wal_level to replica and cleared Patroni logical slots.",
            "Scenario 01 (BUFFERED)": f"wal_level=LOGICAL with no desired slots, wal_level recently became LOGICAL (within {args.wal_level_buffer_hours}h) -> skipped revert entirely, waiting for customer to add slots.",
            "Scenario 01 (SLOT_REMOVED_BUFFER)": f"wal_level=LOGICAL with no desired slots, slot recently removed (within {args.wal_level_buffer_hours}h) -> Patroni slots cleared immediately but wal_level revert deferred.",
            "Scenario 03": f"wal_level={wal_level} (config: desired={len(desired_slots)}, undesired={len(undesired_slots)}) -> synced config table with Patroni DCS (patroni_added={slots_added}, patroni_removed={slots_removed}).",
        }
        summary_msg = scenario_summaries.get(scenario_triggered, "N/A")
        plog("RESULT", f"{scenario_triggered}: {summary_msg}")
        final_msg = (f"Script execution completed. [Scenario: {scenario_triggered}, wal_level: {wal_level}, "
                     f"config_desired: {len(desired_slots)}, config_undesired: {len(undesired_slots)}, "
                     f"patroni_slots: {len(patroni_slots)}, patroni_added: {slots_added}, patroni_removed: {slots_removed}]")
        plog("RESULT", final_msg)
        DL("SUMMARY", final_msg, wal_level=wal_level, scenario=scenario_triggered)
        DL("FINISH", f"Script run finished successfully. [run_id={run_id}]", scenario=scenario_triggered)

    except SystemExit:
        raise  # Allow clean exits (e.g. non-leader node) to pass through without logging as error
    except Exception as e:
        err_msg = f"Script failed with unexpected error: {e}"
        plog("ERROR", err_msg)
        plog("ERROR", traceback.format_exc())
        try:
            db_log(run_id, hostname, cluster_name, "ERROR", err_msg)
        except Exception:
            pass
        sys.exit(1)

if __name__ == "__main__":
    main()
