#!/bin/bash

# Create the plaintext vault content
cat > /tmp/sensitive-values-plaintext.yml << 'VAULTEOF'
# PostgreSQL Passwords
PG_SUPERUSER_PASSWORD: "MyHighlySecurePassword"
PG_REPLICATION_PASSWORD: "MyHighlySecurePassword"
PG_APP_USER_PASSWORD: "MyHighlySecurePassword"

# pgAdmin Credentials
PGADMIN_DEFAULT_EMAIL: "admin@cdc-learning.local"
PGADMIN_DEFAULT_PASSWORD: "MyHighlySecurePassword"
VAULTEOF

# Encrypt the file with Ansible vault
VAULT_DIR="/Users/ajaydwivedi/Documents/Github/Personal/PostgreSQL-Learning/Debezium-CDC-Kafka"
VAULT_PASS_FILE="${VAULT_DIR}/vault-pass"
VAULT_FILE="${VAULT_DIR}/sensitive-values"

# Encrypt it
ansible-vault encrypt /tmp/sensitive-values-plaintext.yml \
  --vault-password-file="${VAULT_PASS_FILE}"

# Copy to the actual location
cp /tmp/sensitive-values-plaintext.yml "${VAULT_FILE}"

echo "✓ Vault file updated with password: MyHighlySecurePassword"
echo "✓ File: ${VAULT_FILE}"

# Verify it can be decrypted
echo ""
echo "Verifying vault file..."
ansible-vault view "${VAULT_FILE}" --vault-password-file="${VAULT_PASS_FILE}" | head -2
