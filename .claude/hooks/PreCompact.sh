#!/usr/bin/env bash
# PreCompact.sh — Fires before Claude compacts (summarises) the conversation.
# Purpose: Persist key session state so nothing is lost across compaction.

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_FILE="$PROJECT_ROOT/.claude/.session-state.md"

echo "=== PreCompact: saving session state ==="

cat > "$STATE_FILE" <<EOF
# Session State — saved $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Git Status
Branch : $(git branch --show-current 2>/dev/null || echo 'n/a')
Staged : $(git diff --cached --name-only 2>/dev/null | tr '\n' ' ' || echo 'none')
Dirty  : $(git diff --name-only 2>/dev/null | tr '\n' ' ' || echo 'none')

## Recent Migrations
$(ls -t "$PROJECT_ROOT/alembic/versions/"*.py 2>/dev/null | head -5 | xargs -I{} basename {} || echo 'none')

## Last Test Run
$(cat "$PROJECT_ROOT/.pytest_cache/lastfailed" 2>/dev/null || echo 'no cache')

## Open TODOs (app/)
$(grep -r "TODO\|FIXME" "$PROJECT_ROOT/app" --include="*.py" -n 2>/dev/null | head -20 || echo 'none')
EOF

echo "Session state written to .claude/.session-state.md"
echo "=== PreCompact done ==="
