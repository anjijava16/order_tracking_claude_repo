# /deploy — Deploy Order Tracking System

## Usage
```
/deploy [environment]
```
`environment` = `staging` | `production` (default: `staging`)

## Pre-Deploy Checklist
Before deploying, confirm all of the following:

1. **Tests pass**
   ```bash
   pytest
   ```
2. **No lint errors**
   ```bash
   ruff check .
   ruff format --check .
   mypy app/
   ```
3. **Pending migrations applied**
   ```bash
   alembic check
   ```
4. **Environment variables set** in target environment:
   - `DATABASE_URL`
   - `REDIS_URL`
   - `JWT_SECRET`
   - `JWT_REFRESH_SECRET`
   - `CARRIER_WEBHOOK_SECRET`

## Deploy Steps

### Staging
```bash
# 1. Push to staging branch (triggers GitHub Actions)
git push origin main:staging

# 2. Monitor GitHub Actions workflow
gh run watch

# 3. Run smoke tests against staging
pytest tests/smoke/ --base-url=https://staging-api.ordertracking.com
```

### Production
```bash
# 1. Create a release tag
git tag -a v$(python -c "import tomllib; print(tomllib.load(open('pyproject.toml','rb'))['project']['version'])") \
  -m "Release $(date +%Y-%m-%d)"
git push origin --tags

# 2. GitHub Actions deploys on tag push
gh run watch

# 3. Verify health endpoint
curl https://api.ordertracking.com/health
```

## Rollback
```bash
# Redeploy previous tag
gh workflow run deploy.yml -f tag=v<previous-version>

# Roll back last Alembic migration
alembic downgrade -1
```

## Post-Deploy Verification
- [ ] `GET /health` returns `200`
- [ ] `GET /api/v1/orders` returns `401` (auth working)
- [ ] FastAPI `/docs` loads correctly
- [ ] Carrier webhook endpoint reachable
- [ ] Celery workers running
