import paramiko
import pandas as pd
from dba_package.process_ssh_key import get_private_key

def get_csv_result_using_ssh(hosts, ssh_key_content, command, timeout_seconds=30, verbose = False):
    # Retrieve SSH Private Key
    private_key = get_private_key(ssh_key_content)

    # if verbose:
    #     print(f"private_key: {private_key}")

    # pt_results = PrettyTable()
    df_results = pd.DataFrame()
    header_set = False

    # pt_failures = PrettyTable()
    # pt_failures.field_names = ["server", "error_message"]
    df_failures = pd.DataFrame(columns=["server_name", "error_message"])

    # For counting
    servers_successful = list()
    servers_failed = list()

    for host in hosts:
        if verbose:
            print(f"working on host {host}..")
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        try:
            ssh.connect(hostname=host, username="ansible", pkey=private_key, timeout=5)
            stdin, stdout, stderr = ssh.exec_command(command, timeout=timeout_seconds)
            output = stdout.read().decode(errors='ignore').strip()
            error = stderr.read().decode().strip()

            # Parse only valid rows (exclude psql noise)
            rows = [line.strip() for line in output.splitlines() if '|~|' in line]
            rowcount = len(rows)-1
            if verbose:
                print(f"rowcount: {rowcount}\n")

            if verbose:
                print(f"output:\n{output}\n")
                # print(f"\nrows: {rows}\n")

            if not header_set:
                # Extract headers
                header_line = rows[0]
                headers = [col.strip() for col in header_line.split('|~|')]
                headers.insert(0,'server_name')

                if verbose:
                    print(f"header: {headers}")

                # pt_results.field_names = headers
                df_results = pd.DataFrame(columns=headers)
                header_set = True

            if rowcount < 1:
                if verbose:
                    print(f"[{host}] No rows returned.")

                if error.strip():
                    # print(f"[{host}] Error:\n{error}")
                    # pt_failures.add_row([host, str(error)])
                    df_failures.loc[len(df_failures)] = [host, str(error)]
                    servers_failed.append(host)
                # continue
                # continue
            else:
                if verbose:
                    print(f"[{host}] extract rows.")

                for row in rows[1:]:
                    # if verbose:
                    #     print(f"\nrow: {row}\n")

                    # Extract data into separate columns using delimiter '|~|'
                    row_data = [col.strip() for col in row.split('|~|')]
                    row_data.insert(0,host)

                    if len(row_data) == len(headers):
                        # if verbose:
                        #     print(f"inserting row in df_results: {row_data}")
                        df_results.loc[len(df_results)] = row_data
                    else:
                        if verbose:
                            print(f"Skipping malformed row: {row_data}")

            servers_successful.append(host)
        except Exception as e:
            # pt_failures.add_row([host, str(e)])
            df_failures.loc[len(df_failures)] = [host, str(e)]
            servers_failed.append(host)
        finally:
            ssh.close()

    # # print result for analysis
    # if verbose:
    #     print(f"df_results: \n{df_results}\n")

    pass_fail_list = {'pass':servers_successful,'fail':servers_failed}

    return df_results, df_failures, pass_fail_list

