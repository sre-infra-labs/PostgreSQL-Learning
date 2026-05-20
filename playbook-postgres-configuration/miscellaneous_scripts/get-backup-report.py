import boto3
from collections import defaultdict
import os, json
import socket
import argparse
from datetime import datetime, timezone, timedelta

from dba_package.send_slack_notification import send_slack_notification
from dba_package.dataframe_to_prettytable import dataframe_to_prettytable
from dba_package.process_inventory import Inventory
import pandas as pd


# Parameters
if 'Declare parameters' == 'Declare parameters':
    parser = argparse.ArgumentParser(description="Script to get Backup Report", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("--inventory_file", "-i", type=str, required=False, action="store", default="hosts.yml", help="Inventory YAML File")
    parser.add_argument(
        "--notification_target", "-n",
        required=False,
        choices=["none", "slack", "email"],
        default="none",
        help="Notification target: choose from 'none', 'slack', or 'email'"
    )
    parser.add_argument(
        "--critical_hours",
        type=int,
        default=60,
        help="Number of hours since the backup has not happened for critical threshold (default: 60)"
    )
    parser.add_argument(
        "--warning_hours",
        type=int,
        default=36,
        help="Number of hours since the backup has not happened for warning threshold (default: 36)"
    )
    parser.add_argument(
        "--retry_attempts",
        type=int,
        default=3,
        help="Number of retries to attempt on failure (default: 3)"
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable extra debug messages")

    args=parser.parse_args()

# Local variables
today = datetime.today()
today_str = today.strftime('%Y-%m-%d')

# Get argument values
if 'Retrieve Parameters' == 'Retrieve Parameters':
    inventory_file = args.inventory_file
    notification_target = args.notification_target
    verbose = args.verbose
    critical_hours = args.critical_hours
    warning_hours = args.warning_hours
    retry_attempts = args.retry_attempts

# Extract environment variables
if 'Retrieve Env Variables' == 'Retrieve Env Variables':
    if verbose:
        print(f"Retrieve Env Variables..")
    clusters_to_ignore = os.getenv("CLUSTERS_TO_IGNORE", "[]")
    clusters_to_ignore = json.loads(clusters_to_ignore)

    aws_access_key = os.getenv("PG_BACKREST_REPO1_S3_KEY")
    aws_access_key_secret = os.getenv("PG_BACKREST_REPO1_S3_KEY_SECRET")
    aws_region = os.getenv("PG_BACKREST_REPO1_S3_BUCKET_REGION")
    # aws_region = 'ap-south-1'
    bucket_name = os.getenv("PG_BACKREST_REPO1_S3_BUCKET_NAME")
    prefix = os.getenv("PG_BACKREST_REPO1_S3_PREFIX")

    dba_slack_users_json =  os.getenv("DBA_SLACK_USERS", "[]")
    dba_team_slack_group_id = os.getenv("DBA_TEAM_SLACK_GROUP_ID", "S000ZZ0ZZ0Z")
    workflow_event_name =  os.getenv("WORKFLOW_EVENT_NAME","user_environment")

# Extract Inventory Contents
if 'Inventory file' == 'Inventory file':
    if verbose:
        print(f"Process inventory file..")
    invObj = Inventory(inventory_file)
    all_hosts = invObj.inventory_hosts
    df_inventory = pd.DataFrame(invObj.inventory_items)
    all_stanzas = df_inventory["stanza_name"].unique().tolist()
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

def get_runner_info():
    runner_hostname = socket.gethostname()
    runner_fqdn = socket.getfqdn()

    # Safer way to get IP (works without DNS lookup)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))  # Google DNS, just to determine outbound IP
        runner_ip_address = s.getsockname()[0]
        s.close()
    except Exception:
        runner_ip_address = "Unavailable"

    return runner_hostname, runner_fqdn, runner_ip_address

def get_backup_info_last_modified(aws_access_key, aws_access_key_secret, aws_region, bucket_name, prefix="pg-backups/backup/"):
    """
    For each top-level directory under the given prefix, 
    get the 'LastModified' date of the 'backup.info' file.
    """
    s3 = boto3.client(
        "s3",
        aws_access_key_id=aws_access_key,
        aws_secret_access_key=aws_access_key_secret,
        region_name=aws_region
    )

    # Get list of top-level folders
    paginator = s3.get_paginator("list_objects_v2")
    response_iterator = paginator.paginate(
        Bucket=bucket_name,
        Prefix=prefix,
        Delimiter="/"
    )

    results = {}
    for page in response_iterator:
        for cp in page.get("CommonPrefixes", []):
            folder = cp["Prefix"]  # e.g., "pg-backups/backup/pgbackrest-stanza-name/"
            backup_info_key = folder + "backup.info"

            try:
                response = s3.head_object(Bucket=bucket_name, Key=backup_info_key)
                last_modified = response["LastModified"]

                # Convert to string for readability
                last_modified_str = last_modified.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S %Z")
                results[folder.rstrip("/").split("/")[-1]] = last_modified_str
            except s3.exceptions.ClientError as e:
                # backup.info might not exist
                results[folder.rstrip("/").split("/")[-1]] = None

    return results

if 'Get Last Backup Time' == 'Get Last Backup Time':
    if verbose:
        print(f"Get last backup")
    if not aws_access_key or not aws_access_key_secret or not aws_region or not bucket_name or not prefix:
        raise EnvironmentError("❌ Missing required AWS env vars: PG_BACKREST_REPO1_S3_KEY, PG_BACKREST_REPO1_S3_KEY_SECRET, PG_BACKREST_REPO1_S3_BUCKET_REGION, PG_BACKREST_REPO1_S3_BUCKET_NAME, PG_BACKREST_REPO1_S3_PREFIX")

    result = []
    try:
        result = get_backup_info_last_modified(aws_access_key, aws_access_key_secret, aws_region, bucket_name, prefix)

        df_results = pd.DataFrame(result.items(), columns=['stanza_name','last_updated_date'])

        # Ensure last_updated_date column is in datetime format
        df_results['last_updated_date'] = pd.to_datetime(df_results['last_updated_date'], utc=True)

        # Filter DataFrame to exclude ignored clusters
        if verbose:
            print(f"clusters_to_ignore: {clusters_to_ignore}")
        df_results = df_results[~df_results['stanza_name'].isin(clusters_to_ignore)]

    except Exception as e:
        print(f"Error occurred in 'Get Last Backup Time' block. Error => \n{e}")
        raise Exception(e)

if 'Process Output' == 'Process Output':
    if verbose:
        print(f"Compute derived prettytables..")

    try:
        subject=f"PostgreSQL Backup Report"
        script_name = os.path.basename(__file__)

        # Compute cutoff timestamp
        warning_cutoff_time = datetime.now(timezone.utc) - timedelta(hours=warning_hours)
        critical_cutoff_time = datetime.now(timezone.utc) - timedelta(hours=critical_hours)

        # additional data for alerting
        df_all_stanzas = pd.DataFrame({'stanza_name': all_stanzas})

        df_joined = df_all_stanzas.merge(df_results, how='left', on='stanza_name')
        df_missing = df_joined[df_joined['last_updated_date'].isna()][['stanza_name']] # retain only required columns

        nostatus_stanzas = df_missing['stanza_name'].tolist()

        # Filter rows older than cutoff
        df_results_issues_critical = df_results[df_results['last_updated_date'] <= critical_cutoff_time]
        df_results_issues_warning = df_results[
                                    (df_results['last_updated_date'] <= warning_cutoff_time) &
                                    (df_results['last_updated_date'] > critical_cutoff_time)
                                ]

        # compute row counts
        total_rows = len(df_results)
        warning_rows = len(df_results_issues_warning)
        critical_rows = len(df_results_issues_critical)
        nostatus_stanzas_counts = len(nostatus_stanzas)

        if verbose:
            print(f"total_stanzas: {len(all_stanzas)}, status_found: {total_rows}, missing_stanzas: {nostatus_stanzas_counts}, critical_rows: {critical_rows}, warning_rows: {warning_rows}")

        # get PrettyTables
        pt_results = dataframe_to_prettytable(df_results).get_string()
        pt_results_issues_critical = dataframe_to_prettytable(df_results_issues_critical).get_string()
        pt_results_issues_warning = dataframe_to_prettytable(df_results_issues_warning).get_string()

        if verbose:
            print(f"pt_results => \n{pt_results}\n")
            print(f"pt_results_issues_critical => \n{pt_results_issues_critical}\n")
            print(f"pt_results_issues_warning => \n{pt_results_issues_warning}\n")
            print(f"nostatus_stanzas => \n{nostatus_stanzas}\n")

    except Exception as e:
        print(f"Error occurred in 'Process Output' block. Error => \n{e}")
        raise Exception(e)

if notification_target == "slack":
    if verbose:
        print(f"Inside slack notification block..")

    slack_alert_required = False
    dba_slack_users = json.loads(dba_slack_users_json)
    primary_dba_slack_id = 'UED14KCLE'
    if len(dba_slack_users) > 0:
        primary_dba = [user for user in dba_slack_users if user.get("role") == "primary_dba"][0]
        if primary_dba:
            # print(f"Primary DBA Slack ID: {primary_dba['member_id']}")
            primary_dba_slack_id = primary_dba['member_id']

    thread_header=f""":fire: *{subject}*
>*Total Backup Stanzas*: {len(all_stanzas)} || *Missing Backups* {nostatus_stanzas_counts} || *Critical Status*: {critical_rows} || *Warning Status*: {warning_rows}
    """

    if (critical_rows+warning_rows+nostatus_stanzas_counts) > 0:
        slack_alert_required = True
        # thread_header = f"""{thread_header}
        #     CC: <@{primary_dba_slack_id}>
        # """
        thread_header = f"""{thread_header}
        CC: <@{primary_dba_slack_id}> <!subteam^{dba_team_slack_group_id}>
        """

    thread_messages=[
            f":eyes: *Total Backup Stanzas*: {len(all_stanzas)} || {':x:' if nostatus_stanzas_counts > 0 else ':white_check_mark:'} *Missing Backups*: {nostatus_stanzas_counts} || {':x:' if critical_rows > 0 else ':white_check_mark:'} *Critical Status*: {critical_rows} || {':x:' if warning_rows > 0 else ':white_check_mark:'} *Warning Status*: {warning_rows}"
        ]

    # 🔹 Add a separator
    thread_messages.append("> *──────────────────────────────*")

    # runner_hostname = socket.gethostname()
    # runner_fqdn = socket.getfqdn()
    # runner_ip_address = socket.gethostbyname(runner_hostname)
    # Usage
    runner_hostname, runner_fqdn, runner_ip_address = get_runner_info()
    print(f"Runner {{Hostname: {runner_hostname} || FQDN: {runner_fqdn} || IP: {runner_ip_address}}}")

    thread_messages.append(f"Runner {{Hostname: {runner_hostname} || FQDN: {runner_fqdn} || IP: {runner_ip_address}}}")

    # 🔹 Add a separator
    thread_messages.append("> *──────────────────────────────*")

    if nostatus_stanzas_counts > 0:
        snippet = dict(type='snippet', filename=f"pgbackrest_missing_stanzas.txt", content=list_to_multiline_string(nostatus_stanzas), initial_comment="> :hourglass_flowing_sand: PGBACKREST Stanzas Missing on S3 Bucket")
        thread_messages.append(snippet)

    if critical_rows > 0:
        snippet = dict(type='snippet', filename=f"pgbackrest_stanzas_in_CRITICAL_state.txt", content=pt_results_issues_critical, initial_comment="> :hourglass_flowing_sand: PGBACKREST Stanzas with Critical State")
        thread_messages.append(snippet)

    if warning_rows > 0:
        snippet = dict(type='snippet', filename=f"pgbackrest_stanzas_in_WARNING_state.txt", content=pt_results_issues_warning, initial_comment="> :hourglass_flowing_sand: PGBACKREST Stanzas with Warning State")
        thread_messages.append(snippet)

    if workflow_event_name != 'schedule':
        slack_alert_required = True

        if total_rows > 0:
            snippet = dict(type='snippet', filename=f"pgbackrest_stanzas_all.txt", content=pt_results, initial_comment="> :white_check_mark: PGBACKREST Stanzas for all servers")
            thread_messages.append(snippet)

    if slack_alert_required:
        send_slack_notification(thread_header, thread_messages)
    else:
        print(f"Slack message not required.")
else:
    print("No slack notification sent.")



