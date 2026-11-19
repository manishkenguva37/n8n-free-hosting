#!/usr/bin/env bash
# Remote deployment script for n8n.
# Runs on the production server via SSH.
# Sets the n8n image tag, pulls, redeploys, and waits for health.
# Environment variables expected (exported or in environment):
#   DEPLOY_DIR         - path where n8n is deployed (default /opt/n8n)
#   N8N_IMAGE_TAG      - n8n Docker image tag (default 2.48.6)
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/n8n}"
IMAGE_TAG="${N8N_IMAGE_TAG:-2.48.6}"
cd "$DEPLOY_DIR"

# Record previous deployed tag for rollback purposes
if [ -f .deployed-version ]; then
  PREV_TAG="$(cat .deployed-version)"
  echo "$PREV_TAG" > .previous-version
  echo "Previous deployed tag: $PREV_TAG"
fi

echo "Deploying n8n tag: $IMAGE_TAG"
echo "$IMAGE_TAG" > .deployed-version

# Pull the referenced image so the container gets the new version
docker compose pull

# Redeploy (up -d recreates containers if the image changed;
# --remove-orphans removes containers for services no longer in compose)
docker compose up -d --remove-orphans

# Wait for n8n to become healthy (ready to accept traffic)
echo "Waiting for n8n to become ready..."
MAX_ATTEMPTS=60
for i in $(seq 1 "$MAX_ATTEMPTS"); do
  HEALTH_STATUS="$(docker inspect -f '{{.State.Health.Status}}' n8n 2>/dev/null || echo unknown)"
  if [ "$HEALTH_STATUS" = "healthy" ]; then
    echo "n8n is healthy."
    break
  fi
  if [ "$i" -eq "$MAX_ATTEMPTS" ]; then
    echo "WARNING: n8n did not become healthy after ${MAX_ATTEMPTS}*5s ($((MAX_ATTEMPTS*5))s). Current status: $HEALTH_STATUS"
  else
    echo "Attempt $i: health status is $HEALTH_STATUS ..."
  fi
  sleep 5
done

# Verify the deployed tag is recorded
CURRENT_TAG="$(cat .deployed-version)"
echo "Deploy complete. Tag: $CURRENT_TAG"
if [ "$CURRENT_TAG" != "$IMAGE_TAG" ]; then
  echo "WARNING: deployed tag ($CURRENT_TAG) differs requested tag ($IMAGE_TAG)"
fi