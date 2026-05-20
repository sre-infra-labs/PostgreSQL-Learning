#!/usr/bin/env python3

import os
# from pathlib import Path
import argparse
from datetime import datetime
# import paramiko
# from paramiko import RSAKey, Ed25519Key
# from paramiko.ssh_exception import SSHException
# from io import StringIO
import os
import platform
from prettytable import PrettyTable
# import yaml
from dba_package.send_email_notification import send_email_notification
from dba_package.send_slack_notification import send_slack_notification
# from miscellaneous_scripts.dba_package.process_inventory import extract_hosts
# from dba_package.process_ssh_key import get_private_key
# from dba_package.filter_pretty_table import filter_pretty_table
from dba_package.execute_psql_using_ssh import execute_psql_using_ssh
from dba_package.process_inventory import Inventory
from dba_package.dataframe_to_prettytable import dataframe_to_prettytable

# Parameters
if 'Declare parameters' == 'Declare parameters':
    parser = argparse.ArgumentParser(description="Script to Run Multi Server PostgreSQL Query using SSH+Psql Method", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
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

# Execute query, and get results
if 'Result Tables' == 'Result Tables':
    if verbose:
        print(f"Execute psql query, and retrieve results..")

    sql_query = r"""
WITH ssl_info AS (
  SELECT version as ssl_version FROM pg_stat_ssl WHERE pid = pg_backend_pid()
)
,ssl_settings AS (
  SELECT
    split_part(current_setting('server_version'), '.', 1) AS server_version,
    MAX(setting) FILTER (WHERE name = 'ssl') AS ssl_flag,
    MAX(setting) FILTER (WHERE name = 'ssl_cert_file') AS ssl_cert_file,
    MAX(setting) FILTER (WHERE name = 'ssl_key_file') AS ssl_key_file,
    MAX(setting) FILTER (WHERE name = 'ssl_ca_file') AS ssl_ca_file
  FROM pg_settings
  WHERE name IN ('ssl', 'ssl_cert_file', 'ssl_key_file', 'ssl_ca_file')
)
,hba_file_lines AS (
  SELECT trim(regexp_split_to_table(pg_read_file(pg_settings.setting), E'\n')) AS line
  FROM pg_settings
  WHERE name = 'hba_file'
)
,filtered_lines AS (
  SELECT line
  FROM hba_file_lines
  WHERE line <> ''
    AND line NOT LIKE '#%'
)
SELECT
  p.server_version,
  s.ssl_version,
  p.ssl_flag,
  EXISTS (
        SELECT 1
        FROM filtered_lines
        WHERE line ~* '^hostssl\s+all\s+all'
    ) as ssl_enforced,
  p.ssl_cert_file,
  p.ssl_key_file,
  p.ssl_ca_file
FROM ssl_info s, ssl_settings p;
"""

    fn_params = dict(
            hosts = all_hosts,
            ssh_key_content = ssh_key_content,
            dbpassword = password,
            sql_query = sql_query,
            query_timeout_seconds = 30,
            verbose = verbose
        )
    df_results, df_failures, pass_fail_list = execute_psql_using_ssh(**fn_params)

    if verbose:
        print(f"\ndf_results => \n{df_results}")
        print(f"\ndf_failures => \n{df_failures}")
        print(f"\npass_fail_list => \n{pass_fail_list}")
        # print(f"\npt_results => \n{pt_results}")
        # print(f"\npt_failures => \n{pt_failures}")

    # For counting
    servers_successful = list()
    servers_failed = list()
    if isinstance(pass_fail_list, dict):
        servers_successful = pass_fail_list['pass']
        servers_failed = pass_fail_list['fail']

if 'Process Output' == 'Process Output' and len(df_results) > 0:
    if verbose:
        print(f"Compute derived prettytables..")

    df_results_ssl_enforced = df_results[df_results.ssl_enforced=='t']
    df_results_ssl_enabled = df_results[(df_results.ssl_enforced=='f') & (df_results.ssl_flag=='on')]
    df_results_nossl = df_results[df_results.ssl_flag=='off']

    # Check count
    subject=f"PostgreSQL SSL Report"
    servers_count = len(all_hosts)
    servers_failed_count = len(servers_failed)
    servers_successful_count = len(servers_successful)
    result_row_count = len(df_results)
    failure_row_count = len(df_failures)
    servers_ssl_enforced_count = len(df_results_ssl_enforced)
    servers_ssl_enabled_count = len(df_results_ssl_enabled)
    servers_nossl_count = len(df_results_nossl)

    # get PrettyTables
    pt_results_ssl_enforced = dataframe_to_prettytable(df_results_ssl_enforced).get_string(fields=["server_name", "server_version", "ssl_flag", "ssl_enforced", "ssl_cert_file"])
    pt_results_ssl_enabled = dataframe_to_prettytable(df_results_ssl_enabled).get_string(fields=["server_name", "server_version", "ssl_flag", "ssl_enforced", "ssl_cert_file"])
    pt_results_nossl = dataframe_to_prettytable(df_results_nossl).get_string(fields=["server_name", "server_version", "ssl_flag", "ssl_enforced", "ssl_cert_file"])
    pt_failures = dataframe_to_prettytable(df_failures).get_string()

    if verbose:
        print(f"\npt_results_ssl_enforced (rows~{servers_ssl_enforced_count}) => \n{pt_results_ssl_enforced}\n")
        print(f"\npt_results_ssl_enabled (rows~{servers_ssl_enabled_count}) => \n{pt_results_ssl_enabled}\n")
        print(f"\npt_results_nossl (rows~{servers_nossl_count}) => \n{pt_results_nossl}\n")

if notification_target == "slack":
    if verbose:
        print(f"Send slack message..")

    thread_header=f":fire: *{subject}*"
    thread_messages=[
            f":eyes: *Total Servers*: {servers_count} || :white_check_mark: *SSL Enforced Servers*: {servers_ssl_enforced_count} || :ok: *SSL Enabled Servers*: {servers_ssl_enabled_count} || :fire: *No SSL Servers*: {servers_nossl_count} || :x: *Failed Servers*: {servers_failed_count}"
        ]

    # 🔹 Add a separator
    # thread_messages.append("> *──────────────────────────────*")
    if servers_ssl_enforced_count > 0:
        snippet = dict(type='snippet', filename=f"ssl_enforced_servers.txt", content=pt_results_ssl_enforced, initial_comment="> :white_check_mark: Servers with SSL Enforced")
        thread_messages.append(snippet)
        # thread_messages.append("> :white_check_mark: Servers with SSL Enabled")
        # thread_messages.append("```" + ssl_enabled_table_html + "```")

    if servers_ssl_enabled_count > 0:
        snippet = dict(type='snippet', filename=f"ssl_enabled_servers.txt", content=pt_results_ssl_enabled, initial_comment="> :ok: Servers with SSL Enabled")
        thread_messages.append(snippet)
        # thread_messages.append("> :white_check_mark: Servers with SSL Enabled")
        # thread_messages.append("```" + ssl_enabled_table_html + "```")

    if servers_nossl_count > 0:
        snippet = dict(type='snippet', filename=f"nossl_servers.txt", content=pt_results_nossl, initial_comment="> :fire: Servers with No SSL")
        thread_messages.append(snippet)
        # thread_messages.append("> :rotating_light: Servers with No SSL")
        # thread_messages.append("```" + nonssl_table_html + "```")

    if servers_failed_count > 0:
        snippet = dict(type='snippet', filename=f"failed_servers.txt", content=pt_failures, initial_comment="> :x: Servers with Failure")
        thread_messages.append(snippet)
        # thread_messages.append("> :x: Servers with Failures")
        # thread_messages.append("```" + failures_table_html + "```")

    send_slack_notification(thread_header, thread_messages)
else:
    print("No slack notification sent.")

if notification_target == "email":
    if verbose:
        print(f"Send email message..")

    html_content = f"""
    <html>
    <body>
        <h3> Summary: </h3>
        <p> <em>Total Servers</em>: {servers_count} || <em>SSL Enforced Servers</em>: {servers_ssl_enforced_count} || <em>SSL Enabled Servers</em>: {servers_ssl_enabled_count} || <em>No SSL Servers</em>: {servers_nossl_count} || <em>Failed Servers</em>: {servers_failed_count} </p>
        <br>
    """

    if servers_ssl_enforced_count > 0:
        html_content += f"""
        <h3>Servers with SSL Enforced</h3>
        <pre style="font-family: monospace; background: #f4f4f4; padding: 1em;">{pt_results_ssl_enforced}</pre>
        <br><br>
        """

    if servers_ssl_enabled_count > 0:
        html_content += f"""
        <h3>Servers with SSL Enabled</h3>
        <pre style="font-family: monospace; background: #f4f4f4; padding: 1em;">{pt_results_ssl_enabled}</pre>
        <br><br>
        """

    if servers_nossl_count > 0:
        html_content += f"""
        <h3>Servers with No SSL</h3>
        <pre style="font-family: monospace; background: #f4f4f4; padding: 1em;">{pt_results_nossl}</pre>
        <br><br>
        """

    if servers_failed_count > 0:
        html_content += f"""
        <h3>Servers with Failure</h3>
        <pre style="font-family: monospace; background: #f4f4f4; padding: 1em;">{pt_failures}</pre>
        <br><br>
        """

    html_content += """
    Regards,<br>
    get-ssl-report-using-ssh.py
    </body>
    </html>
    """

    send_email_notification(subject, html_content)
else:
    print("No email notification sent.")

# Work-Wrappers/wrapper-get-ssl-report-using-ssh.sh