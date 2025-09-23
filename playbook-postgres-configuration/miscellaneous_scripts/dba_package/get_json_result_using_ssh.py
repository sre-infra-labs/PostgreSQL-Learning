import paramiko
import pandas as pd
import json
import time
from dba_package.process_ssh_key import get_private_key

def get_json_result_using_ssh(hosts, ssh_key_content, command, timeout_seconds=30, verbose = False, retry_attempts:int = 0):
    """
    Executes a command on multiple hosts via SSH, expects JSON output,
    and returns results in a DataFrame with retry logic.

    retry_attempts: Number of retries on failures (default: 0)
    retry_delay: Delay (seconds) between retries
    """

    # Retrieve SSH Private Key
    private_key = get_private_key(ssh_key_content)
    retry_delay_second = 10

    # if verbose:
    #     print(f"private_key: {private_key}")

    df_results = pd.DataFrame()
    header_set = False

    df_failures = pd.DataFrame(columns=["server_name", "error_message"])

    # For counting
    servers_successful = list()
    servers_failed = list()

    for host in hosts:
        attempt = 0
        is_successful = False

        while attempt <= retry_attempts and is_successful is False:
            if verbose:
                print(f"Attempt {attempt+1} on host {host}..")
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

            try:
                stmt = "get ssh.connect"
                ssh.connect(hostname=host, username="ansible", pkey=private_key, timeout=5)
                stmt = "get ssh.exec_command"
                stdin, stdout, stderr = ssh.exec_command(command, timeout=timeout_seconds)

                stmt = "stdout_data = stdout.read()"
                if stdout is None:
                    raise Exception("stdout is None — command may have failed to execute")
                stdout_data = stdout.read()
                stmt = "stderr_data = stderr.read()"
                if stderr is None:
                    raise Exception("stderr is None — command may have failed to execute")
                stderr_data = stderr.read()

                if verbose:
                    print(f"\nstdout_data => {stdout_data}\n")
                    print(f"\nstderr_data => {stderr_data}\n")
                output = stdout_data.decode(errors='ignore').strip()
                error = stderr_data.decode().strip()

                if verbose:
                    print(f"error => \n{error}\n")
                    print(f"Output of command is => \n{output}\n")
                    print(f"stmt => \n{stmt}\n")

                stmt = "validate output type, and compute result_data"
                # Parse json output
                if isinstance(output, str):
                    if verbose:
                        print(f'isinstance(output, str): {isinstance(output, str)}')
                    try:
                        result_data = json.loads(output)
                    except json.JSONDecodeError as e:
                        if verbose:
                            print(f"Invalid JSON string: {output}. || Error Message: {e}")
                        raise ValueError(f"Invalid JSON string: {output}. || Error Message: {e}")
                elif isinstance(output, list):
                    if verbose:
                        print(f'isinstance(output, list): {isinstance(output, list)}')
                    result_data  = output
                else:
                    print(f"Unsupported input type. Must be str or list of dicts. \n{output}")
                    raise ValueError(f"Unsupported input type. Must be str or list of dicts. Current output: \n{output}")

                if verbose:
                    print(f"type(result_data): {type(result_data)}")
                    print(f"result_data => \n{result_data}\n")

                if not isinstance(result_data, list):
                    result_data = [result_data]

                stmt = "Convert result_data to dataframe"
                df_srv_result = pd.DataFrame(result_data)
                df_srv_result.insert(0, "server_name", host)

                if verbose:
                    print(f"df_srv_results => \n{df_srv_result}\n")

                if not header_set:
                    df_results = df_srv_result.copy()
                    header_set = True
                else:
                    df_results = pd.concat([df_results, df_srv_result], ignore_index=True)

                servers_successful.append(host)
                is_successful = True
            except Exception as e:
                print(f"*********** [shell command json] Error occurred for host [{host}] at \nline => {stmt} \n{e}\n")
                df_failures.loc[len(df_failures)] = [host, str(e)]
                servers_failed.append(host)
            finally:
                ssh.close()

            attempt += 1
            if is_successful:
                # break;
                pass
            else:
                if attempt <= retry_attempts:
                    time.sleep(retry_delay_second)

    # # print result for analysis
    # if verbose:
    #     print(f"df_results: \n{df_results}\n")

    pass_fail_list = {'pass':servers_successful,'fail':servers_failed}

    return df_results, df_failures, pass_fail_list

