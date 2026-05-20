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
from dba_package.get_csv_result_using_ssh import get_csv_result_using_ssh
from dba_package.df_cols_to_prettysize import df_cols_to_prettysize
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
        "--threshold_used_percent",
        type=float,
        default=0,
        help="Threshold percentage for used disk space (default: 0)"
    )
    parser.add_argument(
        "--priority1_threshold",
        type=float,
        default=70.0,
        help="Threshold percentage for used space to be considered critical state(default: 70)"
    )
    parser.add_argument(
        "--priority2_threshold",
        type=float,
        default=50.0,
        help="Threshold percentage for used space to be considered critical state(default: 70)"
    )
    parser.add_argument("--filter", "-f", type=int, required=False, action="store", default=5, help="Filter for Top X servers from List for Testing")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable extra debug messages")
    parser.add_argument("--only_root", action="store_true", help="Filter result for root partition only")

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
    only_root = args.only_root
    threshold_used_percent = args.threshold_used_percent
    priority1_threshold = args.priority1_threshold
    priority2_threshold = args.priority2_threshold

# Extract environment variables
if 'Retrieve Env Variables' == 'Retrieve Env Variables':
    if verbose:
        print(f"Retrieve Env Variables..")
    # port = int(os.getenv("PGPORT", "5432"))
    # user = os.getenv("PGUSER", "postgres")
    # if platform.system() == "Darwin":
    #     password = os.getenv("PGPWD")
    # else:
    #     password = os.getenv("PGPWD_OFFICE")
    # dbname = os.getenv("PGDATABASE", "postgres")
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
    if verbose:
        # print(all_hosts)
        # all_hosts = all_hosts[:filter]
        pass

def list_to_multiline_string(items: list) -> str:
    """
    Converts a list of items into a multi-line string.
    Each item appears on a new line.

    :param items: List of strings (or other types that can be stringified)
    :return: Multi-line string
    """
    return "\n".join(str(item) for item in items)


# Execute query, and get results
if 'Result Tables' == 'Result Tables':
    if verbose:
        print(f"Execute command using ssh, and retrieve results..")

    # Detect OS and use appropriate df command
    if platform.system() == "Darwin":
        # macOS (BSD df), use block size of 1 MiB and `-P` for POSIX format
        disk_command = r"""
            df -kP | awk 'NR==1 {print "mount_point|~|capacity_mb|~|used_mb|~|available_mb"} NR>1 {printf "%s|~|%.0f|~|%.0f|~|%.0f\n", $6, $2/1024, $3/1024, $4/1024}'
        """
    elif platform.system() == "Linux":
        # Linux (GNU df), use `--output` and strip trailing "M"
        disk_command = r"""
            df -BM --output=target,size,used,avail | awk 'NR==1 {print "mount_point|~|capacity_mb|~|used_mb|~|available_mb"} NR>1 {gsub(/M/,""); print $1"|~|"$2"|~|"$3"|~|"$4}'
        """
    else:
        raise NotImplementedError("Unsupported OS: " + platform.system())

    fn_params = dict(
            hosts = all_hosts,
            ssh_key_content = ssh_key_content,
            command = disk_command,
            timeout_seconds = 30,
            verbose = verbose
        )
    df_results, df_failures, pass_fail_list = get_csv_result_using_ssh(**fn_params)

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

if 'Process Output' == 'Process Output' and len(df_results) > 0:
    if verbose:
        print(f"Compute derived prettytables..")

    subject=f"PostgreSQL Disk Report"
    script_name = os.path.basename(__file__)
    df_failures.insert(0, "Script", script_name)

    # create function to get a custom orderby column
    def get_priority(percentage):
        priority = None
        if percentage > priority1_threshold:
            priority = 1
        elif percentage > priority2_threshold:
            priority = 2
        else:
            priority = 3

        return priority

    # dataframe for all servers
    df_all_servers = pd.DataFrame({'server_name': all_hosts})
    df_joined = df_all_servers.merge(df_results, how='left', on='server_name')
    df_missing = df_joined[df_joined['capacity_mb'].isna()][['server_name']] # retain only required columns
    missing_servers = df_missing['server_name'].tolist()

    # Convert columns type (str -> numeric)
    cols_4_prettysize = ['capacity_mb','used_mb','available_mb']
    df_results[cols_4_prettysize] = df_results[cols_4_prettysize].apply(lambda col: pd.to_numeric(col, errors='coerce'))

    # Add computed column
    df_results["used_percentage"] = ((df_results["used_mb"] / df_results["capacity_mb"]) * 100).round(1)
    df_results["priority"] = df_results["used_percentage"].apply(get_priority)

    # Apply filters
    df_results_filtered = df_results
    if only_root:
        df_results_filtered = df_results_filtered[df_results_filtered.mount_point == '/']
    if threshold_used_percent > 0.0:
        df_results_filtered = df_results_filtered[df_results_filtered.used_percentage >= threshold_used_percent]

    # Sort data
    df_results_filtered = df_results_filtered.sort_values(by=['priority','server_name','used_percentage'], ascending=[True,True,False])

    # filtered dataframes
    df_results_CRITICAL = df_results_filtered[df_results_filtered.priority == 1]

    # Convert to prettysize
    df_results_filtered = df_cols_to_prettysize(df_results_filtered, cols_4_prettysize, input_size='mb')
    df_results_CRITICAL = df_cols_to_prettysize(df_results_CRITICAL, cols_4_prettysize, input_size='mb')

    # Check count
    servers_count = len(all_hosts)
    servers_failed_count = len(servers_failed)
    servers_successful_count = len(servers_successful)
    servers_critical_count = len(df_results_CRITICAL)
    result_row_count = len(df_results_filtered)
    failure_row_count = len(df_failures)
    missing_servers_count = len(missing_servers)

    # get PrettyTables
    pt_results = dataframe_to_prettytable(df_results_filtered).get_string(fields=['server_name', 'mount_point', 'capacity', 'used', 'available', 'used_percentage'])
    pt_results_critical = dataframe_to_prettytable(df_results_CRITICAL).get_string(fields=['server_name', 'mount_point', 'capacity', 'used', 'available', 'used_percentage'])
    pt_failures = dataframe_to_prettytable(df_failures).get_string()
    pt_missing_servers = list_to_multiline_string(missing_servers)

    if verbose:
        print(f"\npt_results (rows~{result_row_count}) => \n{pt_results}\n")

if notification_target == "slack":
    slack_alert_required = False
    dba_slack_users = json.loads(dba_slack_users_json)
    primary_dba_slack_id = 'UED14KCLE'
    if len(dba_slack_users) > 0:
        primary_dba = [user for user in dba_slack_users if user.get("role") == "primary_dba"][0]
        if primary_dba:
            # print(f"Primary DBA Slack ID: {primary_dba['member_id']}")
            primary_dba_slack_id = primary_dba['member_id']
        # else:
        #     print("No primary_dba found")

    thread_header=f""":fire: *{subject}*
>*Disk Issues*: {servers_critical_count} || *Host Connectivity Issues*: {missing_servers_count} || *Script Failures*: {servers_failed_count}
    """

    if (failure_row_count+servers_critical_count+missing_servers_count) > 0:
        slack_alert_required = True
        # thread_header = f"{thread_header} <@{primary_dba_slack_id}> Kindly check for critical ones."
        thread_header = f"""{thread_header}
        CC: <@{primary_dba_slack_id}> <!subteam^{dba_team_slack_group_id}>
        """
        # thread_header = f"""{thread_header}
        #     Issues found. Kindly check.
        #     CC: <@{primary_dba_slack_id}>
        # """

    thread_messages=[
            f":eyes: *Total Servers*: {servers_count} || :white_check_mark: *Successful Servers*: {servers_successful_count} || :fire: *Used Percent > {priority1_threshold}%*: {servers_critical_count} || :fire: *Missing Status*: {missing_servers_count} || :x: *Failed Servers*: {servers_failed_count}"
        ]

    # 🔹 Add a separator
    # thread_messages.append("> *──────────────────────────────*")

    if servers_critical_count > 0:
        snippet = dict(type='snippet', filename=f"priority_disk_report.txt", content=pt_results_critical, initial_comment=f"> :white_check_mark: Disk Report for Servers over {priority1_threshold}% utilized")
        thread_messages.append(snippet)

    if failure_row_count > 0:
        snippet = dict(type='snippet', filename=f"failed_servers.txt", content=pt_failures, initial_comment="> :x: Servers with Failure")
        thread_messages.append(snippet)

    if missing_servers_count > 0:
        snippet = dict(type='snippet', filename=f"servers_with_missing_status.txt", content=pt_missing_servers, initial_comment="> :x: Servers with Missing Status")
        thread_messages.append(snippet)

    if workflow_event_name != 'schedule':
        # manual run
        slack_alert_required = True
        if result_row_count > 0:
            snippet = dict(type='snippet', filename=f"disk_report.txt", content=pt_results, initial_comment="> :white_check_mark: Disk Report for Successful Servers")
            thread_messages.append(snippet)

    if slack_alert_required:
        send_slack_notification(thread_header, thread_messages)
    else:
        print(f"Slack message not required.")
else:
    print("No slack notification sent.")

if notification_target == "email":
    html_content = f"""
    <html>
    <body>
        <h3> Summary: </h3>
        <p> <em>Total Servers</em>: {servers_count} || <em>Successful Servers</em>: {servers_successful_count} || <em>Used Percent > {priority1_threshold}</em>: {servers_successful_count} || <em>Failed Servers</em>: {servers_failed_count} </p>
        <br>
    """

    if result_row_count > 0:
        html_content += f"""
        <h3>Disk Report for Successful Servers</h3>
        <pre style="font-family: monospace; background: #f4f4f4; padding: 1em;">{pt_results}</pre>
        <br><br>
        """

    if failure_row_count > 0:
        html_content += f"""
        <h3>Servers with Failure</h3>
        <pre style="font-family: monospace; background: #f4f4f4; padding: 1em;">{pt_failures}</pre>
        <br><br>
        """

    html_content += """
    Regards,<br>
    get-disk-report.py
    </body>
    </html>
    """

    send_email_notification(subject, html_content)
else:
    print("No email notification sent.")

# python miscellaneous_scripts/get-disk-report.py -i "../volatile/hosts_personal.yml" -n none
# Work-Wrappers/wrapper-get-disk-report.sh
