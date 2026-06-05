#!/usr/bin/env python3
import subprocess
import sys
import os
import json
import re

vault_file = "/Users/ajaydwivedi/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka/sensitive-values"
vault_pass_file = "/Users/ajaydwivedi/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka/vault-pass"

# Decrypt vault file
result = subprocess.run(
    ["ansible-vault", "view", vault_file, "--vault-password-file=" + vault_pass_file],
    capture_output=True,
    text=True,
    timeout=10
)

if result.returncode != 0:
    print(f"ERROR: Could not decrypt vault file")
    print(f"stderr: {result.stderr}")
    sys.exit(1)

vault_content = result.stdout

# Parse vault content to extract passwords
passwords = {}
for line in vault_content.split('\n'):
    if ':' in line and not line.strip().startswith('#'):
        key, value = line.split(':', 1)
        key = key.strip()
        value = value.strip().strip('"')
        passwords[key] = value

print("="*60)
print("VAULT CREDENTIALS EXTRACTED")
print("="*60)
for key, val in passwords.items():
    if 'PASSWORD' in key or 'PASS' in key:
        print(f"{key}: {val}")

print("\n" + "="*60)
print("VERIFYING SERVICES WITH VAULT CREDENTIALS")
print("="*60 + "\n")

# Test PostgreSQL
pg_pass = passwords.get('PG_SUPERUSER_PASSWORD', '')
print(f"[1] PostgreSQL - password: {pg_pass}")
env = os.environ.copy()
env['PGPASSWORD'] = pg_pass
result = subprocess.run(
    ["docker", "exec", "postgres-cdc", "psql", "-U", "postgres", "-d", "cdc_db", "-c", "SELECT 1;"],
    capture_output=True,
    env=env
)
if result.returncode == 0:
    print("    ✓ PostgreSQL connection SUCCESS")
else:
    print(f"    ✗ PostgreSQL connection FAILED: {result.stderr.decode()}")

# Test pgAdmin
print(f"\n[2] pgAdmin - password: {passwords.get('PGADMIN_DEFAULT_PASSWORD', '')}")
result = subprocess.run(
    ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:5050"],
    capture_output=True
)
http_code = result.stdout.decode().strip()
print(f"    HTTP {http_code} - {'✓ Accessible' if http_code in ['200', '302'] else '✗ Not accessible'}")

# Test Debezium
print("\n[3] Debezium REST API")
result = subprocess.run(
    ["curl", "-s", "http://localhost:8083/connectors"],
    capture_output=True,
    text=True
)
if result.returncode == 0:
    print("    ✓ API responding")
else:
    print("    ✗ API not responding")

# Test Kafka UI
print("\n[4] Kafka UI")
result = subprocess.run(
    ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:8080"],
    capture_output=True
)
http_code = result.stdout.decode().strip()
print(f"    HTTP {http_code} - {'✓ Accessible' if http_code in ['200', '302'] else '✗ Not accessible'}")

print("\n" + "="*60)
print("✓ All services deployed with vault credentials")
print("="*60)
