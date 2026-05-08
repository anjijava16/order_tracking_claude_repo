#!/usr/bin/env bash
# .claude/hooks/lint-on-save.sh
# Runs Ruff lint + format check on the saved file.
# Called automatically after every Edit/Write tool use.

set -euo pipefail

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

if [[ -z "$FILE" ]]; then
  echo "[lint-on-save] No file path provided, skipping."
  exit 0
fi

# Only lint Python files
if [[ ! "$FILE" =~ \.py$ ]]; then
  exit 0
fi

echo "[lint-on-save] Linting $FILE ..."

if command -v ruff &>/dev/null; then
  ruff check --fix "$FILE" || {
    echo "[lint-on-save] ❌ Ruff found errors in $FILE"
    exit 1
  }
  ruff format "$FILE"
fi

echo "[lint-on-save] ✅ $FILE passed lint."
