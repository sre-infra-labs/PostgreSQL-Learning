#!/usr/bin/env python3
import subprocess
import sys
import os

vault_file = "/Users/ajaydwivedi/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka/sensitive-values"
vault_pass_file = "/Users/ajaydwivedi/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka/vault-pass"

# Read vault password
with open(vault_pass_file, 'r') as f:
    vault_pass = f.read().strip()

# Decrypt vault file
result = subprocess.run(
    ["ansible-vault", "view", vault_file, "--vault-password-file=" + vault_pass_file],
    capture_output=True,
    text=True,
    timeout=10
)

if result.returncode == 0:
    print(result.stdout)
else:
    print(f"Error: {result.stderr}", file=sys.stderr)
    sys.exit(1)
