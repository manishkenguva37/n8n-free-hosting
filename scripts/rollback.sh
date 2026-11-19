#!/usr/bin/env bash
# Rollback n8n to a previous Docker image tag.
# Usage: ./scripts/rollback.sh <tag>
# If no tag is given, attempts to roll back to the previous deployed tag.
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/n8n}"

# Determine which tag to roll back to
if [ -n "${1:-}" ]; then
  TARGET_TAG="$1"
else
  if [ -f "$DEPLOY_DIR/.previous-version" ]; then
    TARGET_TAG="$(cat "$DEPLOY_DIR/.previous-version")"
  else
    echo "ERROR: No rollback tag specified and no .previous-version file found."
    echo "Usage: $0 <tag>"
    exit 1
  fi
fi

echo "Rolling back n8n to tag: $TARGET_TAG"

# Update the deployed-version marker
echo "$TARGET_TAG" > "$DEPLOY_DIR/.deployed-version"

# Redeploy with the target image tag by overriding the compose variable
N8N_IMAGE_TAG="$TARGET_TAG" docker compose -f "$DEPLOY_DIR/compose.yaml" up -d --remove-orphans

# Wait for health
echo "Waiting for n8n to become healthy after rollback..."
for i in $(seq 1 60); do
  STATUS="$(docker inspect -f '{{.State.Health.Status}}' n8n 2>/dev/null || echo unknown)"
  if [ "$STATUS" = "healthy" ]; then
    echo "n8n is healthy after rollback."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "WARNING: n8n not healthy after 5m post-rollback. Current status: $STATUS"
  fi
  sleep 5
done

CURRENT_TAG="$(cat "$DEPLOY_DIR/.deployed-version")"
echo "Rollback to $TARGET_TAG complete. Current tag: $CURRENT_TAG"