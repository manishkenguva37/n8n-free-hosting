#!/usr/bin/env bash
# Health-check script for n8n deployment.
# Checks /healthz, /healthz/readiness, and webhook endpoint reachability.
# Usage: N8N_PUBLIC_URL=<url> ./scripts/healthcheck.sh
# Relies on curl being available on the runner (it is on GitHub Actions Ubuntu).
set -euo pipefail

BASE_URL="${N8N_PUBLIC_URL:?N8N_PUBLIC_URL must be set as an environment variable}"

# Helper: get HTTP status code for a URL using curl.
# Returns the three-digit status code (e.g., 200, 404, 000 on error).
get_status() {
  local url="$1"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null) || code="000"
  echo "$code"
}

echo "=== n8n Health Check ==="
echo "Public URL: $BASE_URL"

# 1. Liveness: /healthz — confirms the process is reachable
HEALTH=$(get_status "$BASE_URL/healthz")
echo "/healthz: $HEALTH"
if [ "$HEALTH" != "200" ]; then
  echo "FAIL: /healthz returned HTTP $HEALTH (expected 200)"
  exit 1
fi
echo "  n8n process is alive."

# 2. Readiness: /healthz/readiness — confirms database connected and migrated
READY=$(get_status "$BASE_URL/healthz/readiness")
echo "/healthz/readiness: $READY"
if [ "$READY" != "200" ]; then
  echo "FAIL: /healthz/readiness returned HTTP $READY (expected 200)"
  exit 1
fi
echo "  Database is connected and migrations are complete."

# 3. Webhook endpoint reachability
# The webhook base path should be reachable (anything < 500 indicates the proxy
# is routing; 404 is acceptable as it means the path is served, just not found).
WEBHOOK=$(get_status "$BASE_URL/webhook/")
echo "/webhook/: $WEBHOOK"
if [ "$WEBHOOK" = "000" ] || [ "$WEBHOOK" -ge 500 ]; then
  echo "FAIL: /webhook/ unreachable (HTTP $WEBHOOK)"
  exit 1
fi
echo "  Webhook endpoint is reachable (HTTP $WEBHOOK)."

echo ""
echo "All health checks passed."