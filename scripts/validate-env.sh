#!/usr/bin/env bash
# Validate required environment variables from a .env file.
# Usage: ./scripts/validate-env.sh [.env]
# This script reads the file line-by-line and checks that each required variable
# is set to a non-empty value. It prints PASS/FAIL for each variable only;
# never prints the variable values themselves.
set -euo pipefail

FILE="${1:-.env}"

# Required variables for n8n production deployment with Neon PostgreSQL
REQUIRED=(
  "DB_TYPE"
  "DB_POSTGRESDB_HOST"
  "DB_POSTGRESDB_PORT"
  "DB_POSTGRESDB_DATABASE"
  "DB_POSTGRESDB_USER"
  "DB_POSTGRESDB_PASSWORD"
  "DB_POSTGRESDB_SCHEMA"
  "DB_POSTGRESDB_SSL_ENABLED"
  "N8N_ENCRYPTION_KEY"
  "N8N_HOST"
  "N8N_PROTOCOL"
  "N8N_PORT"
  "N8N_EDITOR_BASE_URL"
  "N8N_WEBHOOK_URL"
  "N8N_PROXY_HOPS"
  "GENERIC_TIMEZONE"
  "TZ"
)

FAIL_COUNT=0
for var in "${REQUIRED[@]}"; do
  # Extract the value for this variable from the .env file.
  # We look for a line starting with the variable name followed by '='.
  # The -E flag enables extended regex; ^ anchors to line start so comments are skipped.
  val=$(grep -E "^\s*${var}=" "$FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -z "$val" ]; then
    echo "FAIL: $var"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: $var"
  fi
done

# Additional format check for encryption key: must be a 64-character hex string
enc_val=$(grep -E "^\s*N8N_ENCRYPTION_KEY=" "$FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if [ -n "$enc_val" ]; then
  if ! echo "$enc_val" | grep -qE '^[0-9a-f]{64}$'; then
    echo "FAIL: N8N_ENCRYPTION_KEY (not a valid 64-char hex string)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: N8N_ENCRYPTION_KEY (valid 64-char hex)"
  fi
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "Environment validation failed. $FAIL_COUNT variable(s) missing or invalid."
  exit 1
fi

echo "All $(( ${#REQUIRED[@]} + 1 )) required environment variables are set and valid."