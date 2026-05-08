#!/usr/bin/env bash
# .claude/hooks/pre-commit.sh
# Runs before any Bash tool executes.
# Blocks commits that fail lint/tests or contain sensitive data.

set -euo pipefail

echo "[pre-commit] Running pre-commit checks..."

# 1. Refuse if .env files are staged
if git diff --cached --name-only 2>/dev/null | grep -qE '^\.env'; then
  echo "[pre-commit] ❌ Blocked: .env file is staged. Remove it with: git reset HEAD .env"
  exit 1
fi

# 2. Refuse if secrets patterns are detected in staged Python files
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)
if [[ -n "$STAGED_FILES" ]]; then
  if echo "$STAGED_FILES" | xargs grep -lE '(JWT_SECRET|DATABASE_URL|REDIS_URL)\s*=' 2>/dev/null | grep -v ".env.example"; then
    echo "[pre-commit] ❌ Blocked: Possible hardcoded secret detected in staged files."
    exit 1
  fi
fi

# 3. Run Ruff on staged Python files
STAGED_PY=$(git diff --cached --name-only 2>/dev/null | grep '\.py$' || true)
if [[ -n "$STAGED_PY" ]]; then
  echo "[pre-commit] Running Ruff on staged files..."
  echo "$STAGED_PY" | xargs ruff check || {
    echo "[pre-commit] ❌ Ruff failed. Fix errors before committing."
    exit 1
  }
fi

# 4. Run unit tests
echo "[pre-commit] Running unit tests..."
pytest tests/unit/ --quiet --tb=short || {
  echo "[pre-commit] ❌ Unit tests failed. Fix before committing."
  exit 1
}

echo "[pre-commit] ✅ All checks passed."
