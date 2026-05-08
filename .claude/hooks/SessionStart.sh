#!/usr/bin/env bash
# SessionStart.sh — Fires once when a Claude session begins.
# Purpose: Load project context into Claude's working memory.

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

echo "=== Order Tracking — Session Start ==="
echo "Project root : $PROJECT_ROOT"
echo "Git branch   : $(git branch --show-current 2>/dev/null || echo 'no git')"
echo "Python       : $(python --version 2>/dev/null || echo 'not found')"
echo "Venv active  : ${VIRTUAL_ENV:-none}"
echo ""

# Show any open TODOs in the codebase as a quick reminder
echo "--- Open TODO / FIXME count ---"
grep -r "TODO\|FIXME\|HACK\|XXX" "$PROJECT_ROOT/app" \
  --include="*.py" -l 2>/dev/null | wc -l | xargs echo "files with TODOs:"

# Remind about required env vars
echo ""
echo "--- Required env vars ---"
REQUIRED_VARS=(DATABASE_URL REDIS_URL JWT_SECRET JWT_REFRESH_SECRET CARRIER_WEBHOOK_SECRET)
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "  MISSING: $var"
  else
    echo "  OK     : $var"
  fi
done

echo ""
echo "=== Session ready ==="
