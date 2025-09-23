#!/usr/bin/env python3

import os
from pathlib import Path
import argparse
from datetime import datetime
import json
import platform
from dba_package.send_email_notification import send_email_notification
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
        default=200,
        help="Threshold replication lag in mb (default: 200)"
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


if 'Get Core Metrics' == 'Get Core Metrics':
    if verbose:
        print(f"Get CPU & Memory in json format..")

    shell_command = r"""
        # CPU Load (15 min average)
        load15=$(awk '{print $3}' /proc/loadavg)
        cpu_count=$(nproc)
        cpu_usage=$(awk -v l="$load15" -v c="$cpu_count" 'BEGIN {printf "%.2f", (l / c) * 100}')

        # Memory and Swap Usage
        mem_used=$(free | awk '/Mem/ {printf("%.2f", $3/$2 * 100)}')
        swap_used=$(free | awk '/Swap/ {if ($2==0) print 0; else printf("%.2f", $3/$2 * 100)}')

        # Output as JSON
        echo "{"
        echo "  \"avg_cpu_percent_15min\": $cpu_usage,"
        echo "  \"memory_used_percent\": $mem_used,"
        echo "  \"swap_used_percent\": $swap_used"
        echo "}"
    """

    fn_params = dict(
            hosts = all_hosts,
            ssh_key_content = ssh_key_content,
            command = shell_command,
            timeout_seconds = 30,
            verbose = verbose
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
        subject=f"Host Core Metrics Report"
        script_name = os.path.basename(__file__)
        df_failures.insert(0, "Script", script_name)

        # additional data for alerting
        df_all_servers = pd.DataFrame({'server_name': all_hosts})
            ## Perform left join, and find missing rowsets
        df_joined = df_all_servers.merge(df_results, how='left', on='server_name')
        df_missing = df_joined[df_joined['memory_used_percent'].isna()][['server_name']] # retain only required columns

        df_results_issues = df_results[
                            (df_results['avg_cpu_percent_15min'] > threshold_cpu_used_percent) |
                            (df_results['memory_used_percent'] > threshold_memory_used_percent)
                        ]

        nostatus_servers = df_missing['server_name'].tolist()

        # Check count
        servers_count = len(all_hosts)
        servers_leaders_count = len(leaders_hosts)
        servers_failed_count = len(servers_failed)
        servers_successful_count = len(servers_successful)
        failure_row_count = len(df_failures)
        result_row_count = len(df_results)
        nostatus_servers_count = len(nostatus_servers)

        # get PrettyTables
        pt_results_issues = dataframe_to_prettytable(df_results_issues).get_string()
        pt_results = dataframe_to_prettytable(df_results).get_string()
            #fields=['server_name', 'mount_point', 'capacity', 'used', 'available', 'used_percentage']

        pt_failures = dataframe_to_prettytable(df_failures).get_string()

        if verbose:
            print(f"\ndf_all_servers (rows~{len(df_all_servers)}) => \n{df_all_servers}\n")
            print(f"\npt_results (rows~{len(df_results)}) => \n{pt_results}\n")
            print(f"\npt_results_issues (rows~{len(df_results_issues)}) => \n{pt_results_issues}\n")
            print(f"nostatus_servers_count: {nostatus_servers_count}")

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
>*Core Metrics Issues*: {len(df_results_issues)} || *Host Connectivity Issues*: {nostatus_servers_count} || *Script Failures*: {len(df_failures)}
    """

    if (len(df_results_issues)+nostatus_servers_count+len(df_failures)) > 0:
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

    if len(df_results_issues) > 0:
        snippet = dict(type='snippet', filename=f"Host Core Metrics Issues.txt", content=pt_results_issues, initial_comment="> :hourglass_flowing_sand: Host Core Metrics Issues")
        thread_messages.append(snippet)

    if nostatus_servers_count > 0:
        snippet = dict(type='snippet', filename=f"missing_status_servers.txt", content=list_to_multiline_string(nostatus_servers), initial_comment="> :hourglass_flowing_sand: Servers with missing metrics")
        thread_messages.append(snippet)

    if failure_row_count > 0:
        snippet = dict(type='snippet', filename=f"Script_Failures.txt", content=pt_failures, initial_comment="> :x: Script Failure Logs")
        thread_messages.append(snippet)

    if workflow_event_name != 'schedule':
        slack_alert_required = True

        if len(df_results) > 0:
            snippet = dict(type='snippet', filename=f"all_hosts_core_metrics.txt", content=pt_results, initial_comment="> :white_check_mark: All Host Core Metrics Report")
            thread_messages.append(snippet)

    if slack_alert_required:
        send_slack_notification(thread_header, thread_messages)
    else:
        print(f"Slack message not required.")
else:
    print("No slack notification sent.")


# Work-Wrappers/wrapper-check-server-health.sh
