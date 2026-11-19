#!/usr/bin/env bash
# Orchestrates n8n deployment from a GitHub Actions job to a remote server.
# This script:
#   1. Validates that all required secrets are set (without echoing values).
#   2. Writes a temporary .env file for Docker Compose from the secrets.
#   3. Copies compose.yaml, Caddyfile, and scripts to the server via SCP.
#   4. Runs the remote deployment script over SSH.
#   5. Runs health checks against the public URL.
#   6. On health check failure, attempts an automatic rollback and re-checks.
#   7. Reports success or failure.
# Exit codes: 0 = success, 1 = failure.
set -euo pipefail

ENV="${1:-development}"  # development or production

# ----- 1. Validate required secrets -----
# List of secrets that must be available in the GitHub Actions job context.
# These are referenced indirectly; their values are never printed.
REQUIRED_SECRETS=(
  "SSH_HOST" "SSH_USERNAME" "SSH_PRIVATE_KEY" "N8N_DOMAIN" "N8N_PUBLIC_URL"
  "DB_POSTGRESDB_HOST" "DB_POSTGRESDB_PORT" "DB_POSTGRESDB_DATABASE"
  "DB_POSTGRESDB_USER" "DB_POSTGRESDB_PASSWORD" "DB_POSTGRESDB_SCHEMA"
  "DB_POSTGRESDB_SSL_ENABLED" "N8N_ENCRYPTION_KEY" "N8N_HOST"
  "N8N_PROTOCOL" "N8N_PORT" "N8N_EDITOR_BASE_URL" "N8N_WEBHOOK_URL"
  "N8N_PROXY_HOPS" "GENERIC_TIMEZONE" "TZ"
)

MISSING=0
for var in "${REQUIRED_SECRETS[@]}"; do
  # ${!var} indirect expansion; -: gives empty if unset
  if [ -z "${!var:-}" ]; then
    echo "MISSING_SECRET: $var"
    MISSING=1
  fi
done

if [ "$MISSING" -eq 1 ]; then
  echo "Aborting deployment: required secrets are not all set."
  exit 1
fi

# ----- 2. Write a temporary .env file for Docker Compose -----
# This .env is generated from GitHub secrets and will not be persisted.
: > .env.ci
# Write each required variable if it has a non-empty value.
for var in DB_TYPE DB_POSTGRESDB_HOST DB_POSTGRESDB_PORT DB_POSTGRESDB_DATABASE \
           DB_POSTGRESDB_USER DB_POSTGRESDB_PASSWORD DB_POSTGRESDB_SCHEMA \
           DB_POSTGRESDB_SSL_ENABLED DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED \
           N8N_ENCRYPTION_KEY N8N_HOST N8N_PROTOCOL N8N_PORT N8N_EDITOR_BASE_URL \
           N8N_WEBHOOK_URL N8N_PROXY_HOPS GENERIC_TIMEZONE TZ; do
  if [ -n "${!var:-}" ]; then
    printf '%s=%s\n' "$var" "${!var}" >> .env.ci
  fi
done
# Optionally add N8N_IMAGE_TAG if set
if [ -n "${N8N_IMAGE_TAG:-}" ]; then
  printf 'N8N_IMAGE_TAG=%s\n' "$N8N_IMAGE_TAG" >> .env.ci
fi

# ----- 3. Write SSH key and set up known hosts -----
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
# Write the private key; GitHub masks secrets in logs, so this is safe.
printf '%s\n' "$SSH_PRIVATE_KEY" > "$HOME/.ssh/id_ed25519"
chmod 600 "$HOME/.ssh/id_ed25519"
# Populate known_hosts to avoid interactive host key prompts
ssh-keyscan -H "$SSH_HOST" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true

# ----- 4. Copy files to the server via SCP -----
# Copy compose.yaml, Caddyfile, and the scripts directory.
DEPLOY_DIR="${DEPLOY_DIR:-/opt/n8n}"
scp -i "$HOME/.ssh/id_ed25519" -o StrictHostKeyChecking=no \
  compose.yaml Caddyfile scripts/ "${SSH_USERNAME}@${SSH_HOST}:${DEPLOY_DIR}/" \
  2>/dev/null || { echo "SCP failed"; exit 1; }

# ----- 5. Run the remote deployment script via SSH -----
# Pass non-secret configuration via environment variables on the remote command line.
ssh -i "$HOME/.ssh/id_ed25519" -o StrictHostKeyChecking=no \
  "${SSH_USERNAME}@${SSH_HOST}" \
  "DEPLOY_DIR=${DEPLOY_DIR} N8N_IMAGE_TAG=${N8N_IMAGE_TAG:-2.48.6} COMPOSE_PROFILES=tls bash -s" \
  < scripts/remote-deploy.sh \
  2>/dev/null || { echo "Remote deploy script failed"; exit 1; }

# ----- 6. Run health checks from this runner -----
export N8N_PUBLIC_URL="${N8N_PUBLIC_URL}"
./scripts/healthcheck.sh || {
  echo "Health check failed; attempting automatic rollback..."
  # Attempt rollback to the tag that was just deployed
  TAG="${N8N_IMAGE_TAG:-2.48.6}"
  ./scripts/rollback.sh "$TAG" || echo "Rollback also failed."
  exit 1
}

echo "Deployment to '$ENV' environment succeeded."
exit 0