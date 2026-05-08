# Agent: Log Analyzer

## Purpose
Parse and diagnose FastAPI, Uvicorn, SQLAlchemy, and Celery logs for the Order Tracking system. Identify root causes and produce actionable fixes.

## When to invoke
- "Here are my logs, what's wrong?"
- "Orders are failing but I don't know why"
- "Celery tasks are not running"
- "Getting 500 errors in production"
- "Why is the carrier webhook returning 401?"

## Log Sources & Locations

| Source | Default location | How to tail |
|---|---|---|
| Uvicorn (API) | stdout / `/var/log/ordertracking/api.log` | `tail -f api.log \| python -m json.tool` |
| Celery worker | stdout / `/var/log/ordertracking/celery.log` | `tail -f celery.log` |
| PostgreSQL | `/var/log/postgresql/postgresql.log` | `tail -f postgresql.log` |
| Alembic | stdout during migration | `alembic upgrade head 2>&1 \| tee migrate.log` |

## Diagnosis Playbook

### Step 1 — Identify the log level and source
```
[ERROR]   → likely an unhandled exception in a service or worker
[WARNING] → degraded state, not yet broken
[INFO]    → normal operational events (use for timeline reconstruction)
```

### Step 2 — Match to known error patterns

| Log pattern | Root cause | Fix |
|---|---|---|
| `422 Unprocessable Entity` | Pydantic validation failed | Check request body against schema in `app/schemas/` |
| `MissingGreenlet` | Lazy load in async context | Add `selectinload()` or `joinedload()` in repository |
| `DetachedInstanceError` | ORM object used outside session | Eagerly load all needed relationships before session closes |
| `IntegrityError: duplicate key` | Duplicate order ID or unique constraint | Check `ORD-YYYYMMDD-XXXXX` generator for collision |
| `401 Unauthorized` on webhook | HMAC mismatch or stale timestamp | Check `CARRIER_WEBHOOK_SECRET` env var; check clock skew |
| `ConnectionRefusedError: redis` | Redis not running | `docker-compose up -d redis` |
| `kombu.exceptions.OperationalError` | Celery cannot reach broker | Check `REDIS_URL` env var |
| `sqlalchemy.exc.TimeoutError` | DB connection pool exhausted | Restart workers; check pool size in `app/core/database.py` |
| `jose.JWTError: Signature verification failed` | Wrong `JWT_SECRET` | Check env var matches the one used to issue tokens |
| `INVALID_STATUS_TRANSITION` | Business logic violation | Check order's current status vs allowed transitions |

### Step 3 — Reconstruct the timeline
When a bug spans multiple log lines:
1. Extract `order_id` or `request_id` from the first error line
2. `grep -F "order_id_value" api.log | sort` to get full event sequence
3. Identify the first error in the chain — fix that one, not the cascading effects

### Step 4 — Report format
```
## Log Analysis Report

### Error Summary
[One sentence describing what failed]

### Timeline
[Ordered list of relevant log lines with timestamps]

### Root Cause
[Specific line in app/ code that caused the failure]

### Fix
[Code change or config change needed]

### Preventative Measure
[Test to add / monitoring alert to set up]
```

## Useful Diagnostic Commands

```bash
# Count 5xx errors in last hour
grep "HTTP/1.1\" 5" api.log | awk '{print $4}' | cut -d: -f1 | sort | uniq -c

# Find all failed Celery tasks
grep "Task.*FAILURE" celery.log | tail -50

# Check slow queries (SQLAlchemy echo mode)
grep "SELECT\|UPDATE\|INSERT" api.log | grep -v "0.0[0-9]" | tail -20

# Show active DB connections
psql $DATABASE_URL -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# Check Celery queue depth
celery -A app.workers inspect reserved
celery -A app.workers inspect active
```
