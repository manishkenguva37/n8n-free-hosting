#!/usr/bin/env bash
# Lightweight secret scanning for tracked files.
# Scans git-tracked files for common secret patterns, excluding .env.example
# and documentation markdown files to reduce false positives.
# Runs in CI; exits non-zero if secrets are detected.
set -euo pipefail

# Patterns that should never appear in tracked source or config (excluding .env.example and .md).
# Each pattern is a basic grep; adjust as needed for your environment.
PATTERNS=(
  "npg_[a-zA-Z0-9]"          # Neon password prefix (avoid printing the value)
  "AKIA[0-9A-Z]{16}"         # AWS Access Key ID
  "sk_live_[0-9a-zA-Z]+"     # Stripe live key
  "rk_live_[0-9a-zA-Z]+"     # Stripe restricted live key
  "xox[baprs]-[0-9a-zA-Z]+"  # Slack token
  "ghp_[A-Za-z0-9]{36}"      # GitHub personal access token
  "github_pat_[A-Za-z0-9_-]+"# GitHub PAT alternative format
  "AIza[0-9A-Za-z\\-_]{35}"  # Google API key
)

# Get list of tracked files (git ls-files). Exclude .env.example and .md files.
TRACKED_FILES=$(git ls-files 2>/dev/null || true)

if [ -z "$TRACKED_FILES" ]; then
  echo "No tracked files (or not a git repo). Skipping secret scan."
  exit 0
fi

FOUND=0
for pattern in "${PATTERNS[@]}"; do
  # Search only in non-markdown, non-.env-example files to avoid flagging docs
  MATCHED=$(echo "$TRACKED_FILES" \
    | grep -v '/.env-example$\|\\.md$' \
    | xargs grep -l "$pattern" 2>/dev/null || true)
  if [ -n "$MATCHED" ]; then
    echo "SECRET DETECTED: pattern '$pattern' matched in:"
    echo "$MATCHED"
    FOUND=1
  fi
done

if [ "$FOUND" -eq 1 ]; then
  echo "Secret scanning found potential secrets. Review the matches above."
  exit 1
fi

echo "No common secrets detected in tracked files."
exit 0