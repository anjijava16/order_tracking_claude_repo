# Order Tracking System — Claude Project

## Project Overview
A full-stack order tracking platform that allows customers to place orders, track shipment status in real time, and receive notifications at every stage of delivery. Admins can manage orders, update statuses, assign carriers, and view analytics.

## Tech Stack
| Layer | Technology |
|---|---|
| Backend API | Python 3.12 + FastAPI |
| Frontend | React + TypeScript |
| Database | PostgreSQL (via SQLAlchemy 2.x async ORM) |
| Migrations | Alembic |
| Validation | Pydantic v2 (request/response schemas) |
| Cache | Redis |
| Queue | Celery + Redis |
| Auth | JWT (python-jose, access + refresh tokens) |
| Testing | pytest + httpx AsyncClient (API), Vitest + React Testing Library (UI) |
| Linting | Ruff (lint + format), mypy (type checking) |
| CI/CD | GitHub Actions |

## Domain Model
```
Customer  ──< Order ──< OrderItem >── Product
                │
                └──< Shipment ──< TrackingEvent
```

### Key Entities
- **Customer** – registered user who places orders
- **Order** – purchase record (status: `pending → confirmed → processing → shipped → delivered | cancelled`)
- **OrderItem** – individual product line on an order
- **Product** – catalogue item with SKU, price, inventory
- **Shipment** – carrier assignment + tracking number tied to an order
- **TrackingEvent** – timestamped status update from carrier (e.g., "Out for delivery")

## Project Structure
```
/
├── app/
│   ├── api/           # FastAPI routers
│   │   └── v1/
│   │       ├── orders.py
│   │       ├── shipments.py
│   │       ├── products.py
│   │       ├── customers.py
│   │       └── tracking.py
│   ├── webhooks/      # Carrier webhook handlers
│   ├── services/      # Business logic (no HTTP, no DB)
│   ├── repositories/  # SQLAlchemy queries (data access layer)
│   ├── workers/       # Celery tasks (email, carrier webhooks)
│   ├── middleware/    # Auth, error handling
│   ├── schemas/       # Pydantic v2 request/response models
│   ├── models/        # SQLAlchemy ORM models
│   ├── core/          # Config, database session, security helpers
│   └── utils/         # Shared helpers
├── alembic/
│   ├── env.py
│   └── versions/      # Migration files
├── frontend/
│   ├── src/
│   │   ├── components/
│   │   ├── pages/
│   │   ├── hooks/
│   │   ├── store/     # Zustand state
│   │   └── api/       # Typed API client
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
└── .claude/
    ├── agents/
    ├── commands/
    ├── hooks/
    ├── rules/
    └── skills/
```

## Common Commands
```bash
# Install dependencies
pip install -r requirements.txt
# or with uv
uv sync

# Run database migrations
alembic upgrade head

# Seed database
python -m app.db.seed

# Start dev server
uvicorn app.main:app --reload

# Start Celery worker
celery -A app.workers worker --loglevel=info

# Run all tests
pytest

# Run tests with coverage
pytest --cov=app --cov-report=term-missing

# Lint + format check
ruff check .
ruff format --check .

# Type check
mypy app/

# Build for production
docker build -t order-tracking .

# Start production server
gunicorn app.main:app -w 4 -k uvicorn.workers.UvicornWorker
```

## Order Status Flow
```
pending → confirmed → processing → shipped → out_for_delivery → delivered
                                           ↘
                                          cancelled (allowed from: pending, confirmed, processing)
```

## API Base URL Conventions
- REST API: `/api/v1/`
- Webhooks (carrier callbacks): `/webhooks/`
- Auth: `/auth/`

## Environment Variables
See `.env.example` for required variables. Never commit `.env` files. Required keys:
- `DATABASE_URL` – PostgreSQL connection string
- `REDIS_URL` – Redis connection string
- `JWT_SECRET` – access token secret
- `JWT_REFRESH_SECRET` – refresh token secret
- `CARRIER_WEBHOOK_SECRET` – HMAC secret for carrier callbacks

## Code Conventions
- Routers validate input (Pydantic schemas) and delegate to services — no business logic in routers
- Services call repositories — no SQLAlchemy calls outside `repositories/`
- All async route handlers use `async def` and raise `HTTPException` — no unhandled exceptions
- Use Pydantic `BaseModel` for all request bodies and response models
- Timestamps (`created_at`, `updated_at`) are managed by SQLAlchemy — do not set them manually
- Order IDs use the format `ORD-YYYYMMDD-XXXXX` (e.g., `ORD-20260507-00042`)
- Carrier tracking numbers are treated as opaque strings — do not parse them
