#!/usr/bin/env python3

import os
from pathlib import Path
import argparse
from datetime import datetime
import json
import platform
import socket
# from dba_package.send_email_notification import send_email_notification
from dba_package.send_slack_notification import send_slack_notification
from dba_package.process_ssh_key import get_private_key
from dba_package.process_inventory import Inventory
from dba_package.dataframe_to_prettytable import dataframe_to_prettytable
from dba_package.execute_psql_using_ssh import execute_psql_using_ssh
# from dba_package.get_csv_result_using_ssh import get_csv_result_using_ssh
from dba_package.get_json_result_using_ssh import get_json_result_using_ssh
# from dba_package.df_cols_to_prettysize import df_cols_to_prettysize
import pandas as pd

# Parameters
if 'Declare parameters' == 'Declare parameters':
    parser = argparse.ArgumentParser(description="Script to get Multi Server Disk Report", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("--inventory_file", "-i", type=str, required=False, action="store", default="hosts.yml", help="Inventory YAML File")
    parser.add_argument(
        "--notification_target", "-n",
        required=False,
        choices=["none", "slack", "email"],
        default="none",
        help="Notification target: choose from 'none', 'slack', or 'email'"
    )
    parser.add_argument(
        "--threshold_repl_lag_mb",
        type=float,
        default=500,
        help="Threshold replication lag in mb (default: 500)"
    )
    parser.add_argument(
        "--threshold_cpu_used_percent",
        type=float,
        default=70,
        help="Threshold cpu usage percent (default: 70)"
    )
    parser.add_argument(
        "--threshold_memory_used_percent",
        type=float,
        default=80,
        help="Threshold memory usage percent (default: 80)"
    )
    parser.add_argument(
        "--retry_attempts",
        type=int,
        default=3,
        help="Number of retries to attempt on failure (default: 3)"
    )
    parser.add_argument("--filter", "-f", type=int, required=False, action="store", default=6, help="Filter for Top X servers from List for Testing")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable extra debug messages")

    args=parser.parse_args()

# Local variables
today = datetime.today()
today_str = today.strftime('%Y-%m-%d')

# Get argument values
if 'Retrieve Parameters' == 'Retrieve Parameters':
    inventory_file = args.inventory_file
    notification_target = args.notification_target
    filter = args.filter
    verbose = args.verbose
    threshold_repl_lag_mb = args.threshold_repl_lag_mb
    threshold_cpu_used_percent = args.threshold_cpu_used_percent
    threshold_memory_used_percent = args.threshold_memory_used_percent
    retry_attempts = args.retry_attempts

# Extract environment variables
if 'Retrieve Env Variables' == 'Retrieve Env Variables':
    if verbose:
        print(f"Retrieve Env Variables..")
    port = int(os.getenv("PGPORT", "5432"))
    user = os.getenv("PGUSER", "postgres")
    if platform.system() == "Darwin":
        password = os.getenv("PGPWD")
    else:
        password = os.getenv("PGPWD_OFFICE")
    dbname = os.getenv("PGDATABASE", "postgres")
    ssh_key_content = os.getenv("ANSIBLE_SSH_PRIVATE_KEY")
    dba_slack_users_json =  os.getenv("DBA_SLACK_USERS", "[]")
    dba_team_slack_group_id = os.getenv("DBA_TEAM_SLACK_GROUP_ID", "S000ZZ0ZZ0Z")
    workflow_event_name =  os.getenv("WORKFLOW_EVENT_NAME","user_environment")

    # Some servers always have error. So ignore then.
    hosts_to_ignore =  os.getenv("HOSTS_TO_IGNORE", "[]")


# Retrieve SSH Private Key
private_key = get_private_key(ssh_key_content)

# Extract Inventory Contents
if 'Inventory file' == 'Inventory file':
    if verbose:
        print(f"Process inventory file..")
    invObj = Inventory(inventory_file)
    all_hosts = invObj.inventory_hosts
    leaders_hosts = invObj.get_hosts_from_group(group_name='leaders')
    if verbose:
        # print(all_hosts)
        # all_hosts = all_hosts[:filter]
        # leaders_hosts = leaders_hosts[:filter]
        pass

def list_to_multiline_string(items: list) -> str:
    """
    Converts a list of items into a multi-line string.
    Each item appears on a new line.

    :param items: List of strings (or other types that can be stringified)
    :return: Multi-line string
    """
    return "\n".join(str(item) for item in items)

if 'Get Patroni Cluster State' == 'Get Patroni Cluster State':
    if verbose:
        print(f"Get Patroni Cluster State in json format..")

    shell_command = r"""
        sudo patronictl -c /etc/patroni/patroni.yml list -f json
    """

    fn_params = dict(
            hosts = leaders_hosts,
            ssh_key_content = ssh_key_content,
            command = shell_command,
            timeout_seconds = 30,
            verbose = verbose,
            retry_attempts = retry_attempts
        )
    df_results, df_failures, pass_fail_list = get_json_result_using_ssh(**fn_params)

    if verbose:
        print(f"\ndf_results => \n{df_results}")
        print(f"\ndf_failures => \n{df_failures}")
        print(f"\npass_fail_list => \n{pass_fail_list}")

    # For counting
    servers_successful = list()
    servers_failed = list()
    if isinstance(pass_fail_list, dict):
        servers_successful = pass_fail_list['pass']
        servers_failed = pass_fail_list['fail']


if 'Process Output' == 'Process Output':
    if verbose:
        print(f"Compute derived prettytables..")

    try:
        subject=f"Patroni Cluster Health Report"
        script_name = os.path.basename(__file__)
        df_failures.insert(0, "Script", script_name)

        possible_leader_roles = ['Leader','Standby Leader']
        possible_roles = ['Leader','Standby Leader','Replica','Sync Standby']
        possible_states = ['running','streaming']

        # additional data for alerting
        df_results_grouped = df_results.groupby("server_name").size().reset_index(name="row_count")
        df_leaders = pd.DataFrame({'server_name': leaders_hosts})
        df_all_servers = pd.DataFrame({'server_name': all_hosts})
            ## Perform left join, and find missing rowsets
        df_joined = df_leaders.merge(
                df_results_grouped[['server_name','row_count']],  # only required columns
                how='left',
                on='server_name'
                # left_on='server_name',
                # right_on='server_name'
            )
            ## Filter for unmatched rows (i.e., where no corresponding row in grouped data)
        df_missing = df_joined[df_joined['row_count'].isna()][['server_name']] # retain only required columns

        # Ensure 'Lag in MB' column exists and fill NaNs with 0 (or some default)
        if 'Lag in MB' in df_results.columns:
            df_results['Lag in MB'] = pd.to_numeric(df_results['Lag in MB'], errors='coerce').fillna(0)
        else:
            df_results['Lag in MB'] = 0

        df_results_issues = df_results[
                            (~df_results['Role'].isin(possible_roles)) |
                            (~df_results['State'].isin(possible_states)) |
                            (df_results['Lag in MB'] > threshold_repl_lag_mb)
                        ]

        nostatus_servers = df_missing['server_name'].tolist()
        # Skip servers that always have errors
        if len(hosts_to_ignore) > 0 and len(nostatus_servers) > 0:
            print(f"hosts_to_ignore is not null. So skipping some hosts..")
            nostatus_servers = [host for host in nostatus_servers if host not in hosts_to_ignore]
        noreplica_servers = df_results_grouped[df_results_grouped.row_count < 3]['server_name'].tolist()

        # Check count
        servers_count = len(all_hosts)
        servers_leaders_count = len(leaders_hosts)
        servers_failed_count = len(servers_failed)
        servers_successful_count = len(servers_successful)
        failure_row_count = len(df_failures)
        result_row_count = len(df_results)
        result_count = len(df_results_grouped)
        nostatus_servers_count = len(nostatus_servers)
        noreplica_servers_count = len(noreplica_servers)

        # get PrettyTables
        pt_results = dataframe_to_prettytable(df_results).get_string()
        pt_results_issues = dataframe_to_prettytable(df_results_issues).get_string()
            #fields=['server_name', 'mount_point', 'capacity', 'used', 'available', 'used_percentage']

        pt_failures = dataframe_to_prettytable(df_failures).get_string()

        if verbose:
            print(f"\ndf_all_servers (rows~{len(df_all_servers)}) => \n{df_all_servers}\n")
            print(f"\ndf_leaders (rows~{len(df_leaders)}) => \n{df_leaders}\n")

            print(f"\npt_results (rows~{len(df_results)}) => \n{pt_results}\n")

            print(f"\npt_results_issues (rows~{len(df_results_issues)}) => \n{pt_results_issues}\n")
            print(f"\nnostatus_servers (rows~{nostatus_servers_count}) => \n{nostatus_servers}\n")
            print(f"\nnoreplica_servers (rows~{noreplica_servers_count}) => \n{noreplica_servers}\n")

            print(f"nostatus_servers_count: {nostatus_servers_count}")
            print(f"noreplica_servers_count: {noreplica_servers_count}")

            print(f"\npt_failures (rows~{len(df_failures)}) => \n{pt_failures}\n")
    except Exception as e:
        print(f"Error occurred in 'Process Output' block. Error => \n{e}")
        raise Exception(e)


if notification_target == "slack":
    slack_alert_required = False
    dba_slack_users = json.loads(dba_slack_users_json)
    primary_dba_slack_id = 'UED14KCLE'
    if len(dba_slack_users) > 0:
        primary_dba = [user for user in dba_slack_users if user.get("role") == "primary_dba"][0]
        if primary_dba:
            # print(f"Primary DBA Slack ID: {primary_dba['member_id']}")
            primary_dba_slack_id = primary_dba['member_id']

    thread_header=f""":fire: *{subject}*
>*Patroni Cluster State Issues*: {len(df_results_issues)} || *Missing Patroni Status*: {nostatus_servers_count} || *Patroni Replica Unhealthy*: {noreplica_servers_count} || *Script Failures*: {len(df_failures)}
    """

    # if (len(df_results_issues)+nostatus_servers_count+noreplica_servers_count+len(df_failures)) > 0:
    if (len(df_results_issues)+nostatus_servers_count+noreplica_servers_count) > 0:
        slack_alert_required = True
        # thread_header = f"""{thread_header}
        #     CC: <@{primary_dba_slack_id}>
        # """
        thread_header = f"""{thread_header}
        CC: <@{primary_dba_slack_id}> <!subteam^{dba_team_slack_group_id}>
        """

    thread_messages=[
            f":eyes: *Total Servers*: {servers_count} || :white_check_mark: *Successful Executions*: {servers_successful_count} || :x: *Failed Executions*: {servers_failed_count}"
        ]

    # 🔹 Add a separator
    thread_messages.append("> *──────────────────────────────*")

    runner_hostname = socket.gethostname()
    runner_fqdn = socket.getfqdn()
    runner_ip_address = socket.gethostbyname(runner_hostname)

    thread_messages.append(f"Runner {{Hostname: {runner_hostname} || FQDN: {runner_fqdn} || IP: {runner_ip_address}}}")

    # 🔹 Add a separator
    thread_messages.append("> *──────────────────────────────*")

    if len(df_results_issues) > 0:
        snippet = dict(type='snippet', filename=f"patroni_cluster_health_issues.txt", content=pt_results_issues, initial_comment="> :hourglass_flowing_sand: Patroni Cluster Health Issues")
        thread_messages.append(snippet)

    if nostatus_servers_count > 0:
        snippet = dict(type='snippet', filename=f"patroni_cluster_missing_status.txt", content=list_to_multiline_string(nostatus_servers), initial_comment="> :hourglass_flowing_sand: Missing Patroni Cluster Health Check")
        thread_messages.append(snippet)

    if noreplica_servers_count > 0:
        snippet = dict(type='snippet', filename=f"patroni_missing_replica_status.txt", content=list_to_multiline_string(noreplica_servers), initial_comment="> :hourglass_flowing_sand: Missing Patroni Replica Health Status")
        thread_messages.append(snippet)

    if failure_row_count > 0:
        snippet = dict(type='snippet', filename=f"Script_Failures.txt", content=pt_failures, initial_comment="> :x: Script Failure Logs")
        thread_messages.append(snippet)

    if workflow_event_name != 'schedule':
        slack_alert_required = True

        if len(df_results) > 0:
            snippet = dict(type='snippet', filename=f"result.txt", content=pt_results, initial_comment="> :white_check_mark: Patroni Cluster Report")
            thread_messages.append(snippet)

    if slack_alert_required:
        send_slack_notification(thread_header, thread_messages)
    else:
        print(f"Slack message not required.")
else:
    print("No slack notification sent.")


# Work-Wrappers/wrapper-check-server-health.sh
