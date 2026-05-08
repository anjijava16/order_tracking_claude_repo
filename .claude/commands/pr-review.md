# /pr-review — Pull Request Review

## Usage
```
/pr-review <pr-number>
```
Example: `/pr-review 87`

## Step 1 — Fetch the PR
```bash
gh pr view <pr-number> --json title,body,files,additions,deletions
gh pr diff <pr-number>
```

## Step 2 — Review Checklist

### Architecture
- [ ] Routers only validate + delegate (no business logic)
- [ ] All DB queries are in `app/repositories/`
- [ ] Services are pure (no `Request`/`Response` references)

### Domain Correctness
- [ ] Order status transitions follow the valid state machine
- [ ] Order ID format `ORD-YYYYMMDD-XXXXX` used correctly
- [ ] Carrier tracking numbers treated as opaque strings

### Security
- [ ] New routes use `Depends(get_current_user)`
- [ ] Carrier webhooks use `hmac.compare_digest()` — not `==`
- [ ] No secrets or PII in logs
- [ ] Input validated by Pydantic schema before service call

### Tests
- [ ] New logic has corresponding unit tests in `tests/unit/`
- [ ] API changes have integration tests in `tests/integration/`
- [ ] Edge cases covered (invalid status, missing fields, unauthorized access)

### Code Quality
- [ ] All functions and parameters are type-annotated
- [ ] No bare `except:` — catch specific exceptions
- [ ] No blocking I/O inside `async def` (no `requests`, no sync DB calls)
- [ ] Ruff + mypy pass with no new errors

## Step 3 — Post Review Comment
```bash
gh pr review <pr-number> \
  --comment \
  --body "## Review Notes

### Looks Good
- [what is well done]

### Needs Changes
- [specific file + line + issue]

### Suggestions
- [optional improvements]"
```

## Step 4 — Approve or Request Changes
```bash
# Approve
gh pr review <pr-number> --approve

# Request changes
gh pr review <pr-number> --request-changes --body "Please address the items above."
```
