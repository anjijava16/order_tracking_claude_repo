# /fix-issue — Fix a GitHub Issue

## Usage
```
/fix-issue <issue-number>
```
Example: `/fix-issue 42`

## Workflow

### Step 1 — Fetch the Issue
```bash
gh issue view <issue-number>
```
Read the issue title, description, and any linked PRs or comments.

### Step 2 — Understand the Domain Impact
Determine which layer is affected:
- **Order status bug** → `app/services/order_status_service.py`
- **API validation bug** → router + Pydantic schema in `app/schemas/`
- **Database/query bug** → `app/repositories/`
- **Webhook processing bug** → `app/webhooks/` + `app/workers/`
- **Frontend bug** → `frontend/src/`

### Step 3 — Reproduce Locally
```bash
# Run related tests first to see failure
pytest tests/ -k "<keyword>" -s -v
```

### Step 4 — Implement the Fix
- Stay in the correct layer (no cross-layer changes unless necessary)
- Follow the code conventions in `CLAUDE.md`
- Keep the fix minimal — do not refactor unrelated code

### Step 5 — Add/Update Tests
```bash
# Confirm tests pass
pytest tests/ -k "<keyword>"
pytest  # full suite
```

### Step 6 — Create a Branch and Commit
```bash
git checkout -b fix/issue-<number>-<short-description>
git add -p
git commit -m "fix: <description> (closes #<number>)"
```

### Step 7 — Open a PR
```bash
gh pr create \
  --title "fix: <description>" \
  --body "Closes #<issue-number>

## Changes
- [describe changes]" \
  --assignee @me
```
