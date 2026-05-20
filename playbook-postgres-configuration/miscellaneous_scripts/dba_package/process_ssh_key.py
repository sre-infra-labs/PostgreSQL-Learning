# import get_temp_ssh_key_file
import os
import tempfile
from paramiko import RSAKey, Ed25519Key
from paramiko.ssh_exception import SSHException
from io import StringIO

def get_temp_ssh_key_file(ssh_key_content:str):
    '''
    Purpose: Retrieve ANSIBLE_SSH_PRIVATE_KEY, save it to a temp file, and return file path
    '''
    tmp_key_file = tempfile.NamedTemporaryFile(delete=False, mode="w", prefix="ssh_key_", suffix=".pem")
    tmp_key_file.write(ssh_key_content)
    tmp_key_file.flush()
    os.chmod(tmp_key_file.name, 0o600)
    return tmp_key_file.name

def get_private_key(ssh_key_content:str):
    '''
    Purpose: Receive SSH Private Key string, and return valid Private key
    '''
    private_key = None
    if not ssh_key_content:
        raise EnvironmentError("[ssh_key_content] parameter is mandatory")
    else:
        try:
            private_key = RSAKey.from_private_key(StringIO(ssh_key_content))
        except SSHException:
            try:
                private_key = Ed25519Key.from_private_key(StringIO(ssh_key_content))
            except SSHException as e:
                raise ValueError("Invalid SSH private key format or unsupported key type") from e

    return private_key