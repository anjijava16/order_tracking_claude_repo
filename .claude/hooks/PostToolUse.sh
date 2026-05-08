#!/usr/bin/env bash
# PostToolUse.sh — Fires after EVERY Edit or Write tool use.
# Purpose: Auto-lint and auto-format any Python file that was just changed.
# Replaces the older lint-on-save.sh (kept for backwards compatibility).

set -euo pipefail

# FILE is injected by Claude Code as the path that was just edited/written.
FILE="${CLAUDE_FILE_PATH:-}"

if [ -z "$FILE" ]; then
  exit 0
fi

# Only act on Python files
if [[ "$FILE" != *.py ]]; then
  exit 0
fi

# Must be inside the project
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [[ "$FILE" != "$PROJECT_ROOT"* ]]; then
  exit 0
fi

echo "PostToolUse: linting $FILE"

# Auto-fix lint issues, then format
ruff check --fix "$FILE" 2>&1 || true
ruff format "$FILE" 2>&1 || true

echo "PostToolUse: done"
