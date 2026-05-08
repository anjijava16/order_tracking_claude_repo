# Command: /audit

Run a full security and code quality audit on the Order Tracking codebase before a release or on-demand.

## Usage
```
/audit              # Full audit
/audit security     # Security checks only
/audit quality      # Code quality only
/audit deps         # Dependency vulnerabilities only
```

## Audit Checklist

### 1. Security — Authentication & Authorization
- [ ] Every non-public route has `Depends(get_current_user)`
- [ ] Customer routes check `current_user.id == resource.customer_id`
- [ ] Admin-only routes check `current_user.role == "admin"`
- [ ] `/webhooks/carrier` verifies HMAC with `hmac.compare_digest()`
- [ ] Webhook handler checks `abs(now - timestamp) <= 300`
- [ ] No JWT secrets hardcoded in source — all from `settings`
- [ ] `JWT_SECRET` and `JWT_REFRESH_SECRET` are different values

### 2. Security — Input Validation
- [ ] All request bodies use Pydantic v2 `BaseModel` from `app/schemas/`
- [ ] Pagination limit capped: `min(limit, 100)` in all repository queries
- [ ] No raw SQL string interpolation anywhere in `app/`
- [ ] No `eval()`, `exec()`, `subprocess` with user-supplied input

### 3. Security — Data Exposure
- [ ] Error responses use envelope format — no raw exception messages to client
- [ ] No PII logged (email, address, payment info)
- [ ] `.env` and `.env.*` in `.gitignore`
- [ ] `git log --all -- .env` returns empty (no accidental commit history)

### 4. Code Quality — Architecture
- [ ] No SQLAlchemy calls outside `app/repositories/`
- [ ] No business logic in `app/api/v1/` routers
- [ ] No `HTTPException` raises in `app/services/` (use domain exceptions from `app/core/exceptions.py`)
- [ ] All async route handlers use `async def`
- [ ] No `session.commit()` in routers or services — only in repositories

### 5. Code Quality — Types & Linting
```bash
ruff check app/ tests/
mypy app/ --strict
```
- [ ] Zero ruff errors
- [ ] Zero mypy errors

### 6. Dependency Vulnerabilities
```bash
pip audit
```
- [ ] No CRITICAL or HIGH CVEs in production dependencies

### 7. Test Coverage
```bash
pytest --cov=app --cov-report=term-missing
```
- [ ] Services: ≥ 90% coverage
- [ ] Repositories: ≥ 80% coverage
- [ ] Routers: ≥ 70% coverage

### 8. Database
- [ ] All new columns have migrations in `alembic/versions/`
- [ ] `alembic check` returns "No new upgrade operations detected"
- [ ] Required indexes present: `orders.customer_id`, `orders.status`, `shipments.tracking_number`, `tracking_events.shipment_id`

## Automated Audit Commands

```bash
# Run everything in sequence, fail fast
set -e

echo "=== Ruff lint ==="
ruff check app/ tests/

echo "=== Mypy types ==="
mypy app/

echo "=== Dependency CVEs ==="
pip audit

echo "=== Migration check ==="
alembic check

echo "=== Test coverage ==="
pytest --cov=app --cov-report=term-missing --cov-fail-under=80

echo "=== Audit PASSED ==="
```

## Output Format
Report findings as:
```
[PASS] or [FAIL] + finding description + file:line if applicable
```
Group by severity: CRITICAL → HIGH → MEDIUM → LOW
Always end with a summary line: `Audit complete: N issues found (X critical, Y high, Z medium)`
