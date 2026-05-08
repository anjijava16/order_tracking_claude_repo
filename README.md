# Order Tracking System

A production-grade, full-stack order tracking platform. Customers place orders, track real-time shipment status, and receive notifications at every delivery stage. Admins manage orders, assign carriers, and view analytics. This system integrates with multiple downstream teams — Inventory, Payments, Notifications, Carrier, and Analytics.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Domain Model](#2-domain-model)
3. [Order Lifecycle & State Machine](#3-order-lifecycle--state-machine)
4. [Project Structure](#4-project-structure)
5. [Tech Stack](#5-tech-stack)
6. [Team Boundaries & Integrations](#6-team-boundaries--integrations)
7. [Local Development Setup](#7-local-development-setup)
8. [Environment Variables](#8-environment-variables)
9. [Database — Schema & Migrations](#9-database--schema--migrations)
10. [Backend API Deep Dive](#10-backend-api-deep-dive)
11. [Authentication & Authorization](#11-authentication--authorization)
12. [Async Workers (Celery)](#12-async-workers-celery)
13. [Carrier Webhook Integration](#13-carrier-webhook-integration)
14. [Frontend Architecture](#14-frontend-architecture)
15. [Testing Strategy](#15-testing-strategy)
16. [CI/CD Pipeline](#16-cicd-pipeline)
17. [Deployment](#17-deployment)
18. [Observability — Logs, Metrics, Tracing](#18-observability--logs-metrics-tracing)
19. [Security Considerations](#19-security-considerations)
20. [Contributing Guide](#20-contributing-guide)
21. [Runbook — Common Incidents](#21-runbook--common-incidents)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          CLIENT LAYER                               │
│   Browser (React + TypeScript)    Mobile (future — React Native)    │
└────────────────────┬────────────────────────────────────────────────┘
                     │  HTTPS (JWT in Authorization header)
┌────────────────────▼────────────────────────────────────────────────┐
│                          API GATEWAY / NGINX                        │
│   Rate limiting · TLS termination · Request routing                 │
└────────┬────────────────────────────────────┬───────────────────────┘
         │                                    │
┌────────▼─────────┐                ┌─────────▼────────────┐
│   FastAPI App    │                │   FastAPI App        │
│   Instance 1     │      ...       │   Instance N         │
│  (Gunicorn +     │                │  (Gunicorn +         │
│  Uvicorn worker) │                │  Uvicorn worker)     │
└────────┬─────────┘                └─────────┬────────────┘
         │                                    │
         └──────────────┬─────────────────────┘
                        │
          ┌─────────────▼──────────────┐
          │      Shared Services       │
          │  ┌──────────┐ ┌─────────┐  │
          │  │PostgreSQL│ │  Redis  │  │
          │  │(primary) │ │(cache + │  │
          │  │+ replica │ │ queue)  │  │
          │  └──────────┘ └─────────┘  │
          └────────────────────────────┘
                        │
          ┌─────────────▼──────────────┐
          │      Celery Workers        │
          │  email · carrier · reports │
          └─────────────┬──────────────┘
                        │
     ┌──────────────────┼──────────────────────┐
     │                  │                      │
┌────▼────┐     ┌───────▼──────┐     ┌────────▼───────┐
│Inventory│     │  Payments    │     │ Notifications  │
│  Team   │     │    Team      │     │     Team       │
│  API    │     │    API       │     │  (Email/SMS)   │
└─────────┘     └──────────────┘     └────────────────┘
     │
┌────▼──────────┐     ┌────────────────┐
│  Carrier APIs │     │ Analytics Team │
│ (FedEx, UPS,  │     │  (Data Lake /  │
│  DHL, USPS)   │     │   Warehouse)   │
└───────────────┘     └────────────────┘
```

### Request Flow (Happy Path — Place an Order)

```
1. Customer POSTs /api/v1/orders  (JWT in header)
2. FastAPI auth middleware validates JWT → extracts customer_id
3. Pydantic schema validates request body
4. OrderService.create_order()
   ├── 4a. InventoryService.reserve_items()   → Inventory Team API
   ├── 4b. PaymentsService.authorize()        → Payments Team API
   └── 4c. OrderRepository.save()             → PostgreSQL
5. Celery fires async tasks:
   ├── 5a. send_order_confirmation_email()    → Notifications Team
   └── 5b. emit_order_event()                 → Analytics Team (event stream)
6. FastAPI returns 201 with OrderResponse
```

---

## 2. Domain Model

```
Customer  ──<  Order  ──<  OrderItem  >──  Product
                │
                └──<  Shipment  ──<  TrackingEvent
```

### Entity Descriptions

| Entity | Description | Key Fields |
|---|---|---|
| **Customer** | Registered user who places orders | `id`, `email`, `hashed_password`, `role`, `deleted_at` |
| **Order** | Purchase record with status lifecycle | `id` (`ORD-YYYYMMDD-XXXXX`), `customer_id`, `status`, `total_amount` |
| **OrderItem** | Single product line within an order | `id`, `order_id`, `product_id`, `quantity`, `unit_price` |
| **Product** | Catalogue item with inventory | `id`, `sku`, `name`, `price`, `stock_quantity` |
| **Shipment** | Carrier + tracking number for an order | `id`, `order_id`, `carrier`, `tracking_number`, `status` |
| **TrackingEvent** | Timestamped carrier update | `id`, `shipment_id`, `status`, `location`, `description`, `occurred_at` |

### PostgreSQL Schema (Simplified)

```sql
-- customers
CREATE TABLE customers (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email       VARCHAR(255) UNIQUE NOT NULL,
    hashed_password TEXT NOT NULL,
    role        VARCHAR(50) NOT NULL DEFAULT 'customer',  -- 'customer' | 'admin'
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ
);

-- products
CREATE TABLE products (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku             VARCHAR(100) UNIQUE NOT NULL,
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    price           NUMERIC(10,2) NOT NULL,
    stock_quantity  INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- orders
CREATE TABLE orders (
    id          VARCHAR(25) PRIMARY KEY,  -- ORD-YYYYMMDD-XXXXX
    customer_id UUID NOT NULL REFERENCES customers(id),
    status      VARCHAR(50) NOT NULL DEFAULT 'pending',
    total_amount NUMERIC(10,2) NOT NULL,
    notes       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ
);
CREATE INDEX ix_orders_customer_id ON orders(customer_id);
CREATE INDEX ix_orders_status      ON orders(status);

-- order_items
CREATE TABLE order_items (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id    VARCHAR(25) NOT NULL REFERENCES orders(id),
    product_id  UUID NOT NULL REFERENCES products(id),
    quantity    INTEGER NOT NULL,
    unit_price  NUMERIC(10,2) NOT NULL
);

-- shipments
CREATE TABLE shipments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        VARCHAR(25) NOT NULL REFERENCES orders(id),
    carrier         VARCHAR(100) NOT NULL,
    tracking_number VARCHAR(255) NOT NULL,
    status          VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX ix_shipments_tracking_number ON shipments(tracking_number);

-- tracking_events
CREATE TABLE tracking_events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shipment_id UUID NOT NULL REFERENCES shipments(id),
    status      VARCHAR(100) NOT NULL,
    location    VARCHAR(255),
    description TEXT,
    occurred_at TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX ix_tracking_events_shipment_id ON tracking_events(shipment_id);
```

---

## 3. Order Lifecycle & State Machine

```
                     ┌─────────┐
           POST /    │         │
           orders    │ PENDING │
          ─────────► │         │
                     └────┬────┘
                          │ Admin confirms (payment authorized)
                          ▼
                    ┌───────────┐
                    │ CONFIRMED │
                    └─────┬─────┘
                          │ Warehouse picks & packs
                          ▼
                    ┌────────────┐
                    │ PROCESSING │◄─── Can cancel from here
                    └─────┬──────┘
                          │ Carrier picks up
                          ▼
                     ┌────────┐
                     │SHIPPED │
                     └────┬───┘
                          │ Out for delivery scan
                          ▼
               ┌──────────────────┐
               │ OUT_FOR_DELIVERY │
               └────────┬─────────┘
                         │ Delivered scan
                         ▼
                    ┌───────────┐
                    │ DELIVERED │  (terminal)
                    └───────────┘

  From PENDING, CONFIRMED, or PROCESSING:
                         │
                         ▼
                   ┌───────────┐
                   │ CANCELLED │  (terminal)
                   └───────────┘
```

### Valid Transitions Table

| From | To | Who triggers |
|---|---|---|
| `pending` | `confirmed` | Admin / Payment webhook |
| `pending` | `cancelled` | Customer or Admin |
| `confirmed` | `processing` | Admin / Warehouse system |
| `confirmed` | `cancelled` | Admin |
| `processing` | `shipped` | Admin / Carrier pickup webhook |
| `processing` | `cancelled` | Admin only |
| `shipped` | `out_for_delivery` | Carrier webhook |
| `out_for_delivery` | `delivered` | Carrier webhook |

Any other transition raises `INVALID_STATUS_TRANSITION` (HTTP 409).

---

## 4. Project Structure

```
order-tracking/
│
├── app/                          # Backend Python application
│   ├── main.py                   # FastAPI app factory, router mounting
│   ├── api/
│   │   └── v1/
│   │       ├── __init__.py
│   │       ├── orders.py         # Order CRUD + status endpoints
│   │       ├── shipments.py      # Shipment read endpoints
│   │       ├── products.py       # Product listing
│   │       ├── customers.py      # Customer profile
│   │       └── tracking.py       # Public tracking lookup
│   ├── webhooks/
│   │   └── carrier.py            # Carrier webhook handler (HMAC-verified)
│   ├── services/                 # Pure business logic
│   │   ├── order_service.py
│   │   ├── order_status_service.py  # State machine
│   │   ├── shipment_service.py
│   │   ├── inventory_service.py  # Calls Inventory Team API
│   │   └── payment_service.py    # Calls Payments Team API
│   ├── repositories/             # All SQLAlchemy queries
│   │   ├── order_repository.py
│   │   ├── shipment_repository.py
│   │   ├── product_repository.py
│   │   ├── customer_repository.py
│   │   └── tracking_event_repository.py
│   ├── workers/                  # Celery tasks
│   │   ├── __init__.py           # Celery app factory
│   │   ├── email_tasks.py        # Order confirmation, shipping alerts
│   │   ├── carrier_tasks.py      # Polling fallback for tracking
│   │   └── analytics_tasks.py    # Event emission to data lake
│   ├── schemas/                  # Pydantic v2 models
│   │   ├── order.py
│   │   ├── shipment.py
│   │   ├── product.py
│   │   ├── customer.py
│   │   ├── tracking.py
│   │   └── common.py             # SuccessResponse, ErrorResponse, PaginatedResponse
│   ├── models/                   # SQLAlchemy ORM models
│   │   ├── base.py
│   │   ├── customer.py
│   │   ├── order.py
│   │   ├── order_item.py
│   │   ├── product.py
│   │   ├── shipment.py
│   │   └── tracking_event.py
│   ├── middleware/
│   │   ├── auth.py               # JWT decode → CurrentUser dependency
│   │   └── error_handler.py      # Global exception → error envelope
│   ├── core/
│   │   ├── config.py             # pydantic-settings Settings class
│   │   ├── database.py           # AsyncSession factory + get_db_session
│   │   ├── security.py           # JWT create/verify, password hashing
│   │   └── exceptions.py         # Domain exception classes
│   ├── utils/
│   │   ├── order_id.py           # ORD-YYYYMMDD-XXXXX generator
│   │   └── hmac_verify.py        # Carrier webhook HMAC helper
│   └── db/
│       └── seed.py               # Dev seed data
│
├── alembic/
│   ├── env.py
│   ├── script.py.mako
│   └── versions/                 # Migration files (never edit existing)
│
├── frontend/                     # React + TypeScript SPA
│   ├── src/
│   │   ├── main.tsx
│   │   ├── App.tsx               # Route definitions
│   │   ├── components/           # Reusable UI
│   │   │   ├── OrderCard.tsx
│   │   │   ├── StatusBadge.tsx
│   │   │   ├── TrackingTimeline.tsx
│   │   │   └── Button.tsx
│   │   ├── pages/
│   │   │   ├── OrderListPage.tsx
│   │   │   ├── OrderDetailPage.tsx
│   │   │   ├── TrackingPage.tsx  # Public — no login required
│   │   │   └── LoginPage.tsx
│   │   ├── hooks/
│   │   │   ├── useOrder.ts
│   │   │   └── useTrackingEvents.ts
│   │   ├── store/
│   │   │   └── authStore.ts      # Zustand — current user + tokens
│   │   ├── api/
│   │   │   ├── client.ts         # Axios instance + auth interceptor
│   │   │   ├── orders.ts
│   │   │   ├── shipments.ts
│   │   │   └── tracking.ts
│   │   └── types/                # TypeScript interfaces (mirrors Pydantic)
│   │       ├── order.ts
│   │       ├── shipment.ts
│   │       └── tracking.ts
│   ├── index.html
│   ├── vite.config.ts
│   └── package.json
│
├── tests/
│   ├── conftest.py               # Shared fixtures (db_session, auth_headers)
│   ├── unit/
│   │   ├── test_order_status_service.py
│   │   ├── test_order_id_generator.py
│   │   └── test_hmac_verify.py
│   ├── integration/
│   │   ├── test_create_order.py
│   │   ├── test_order_status_transitions.py
│   │   ├── test_carrier_webhook.py
│   │   └── test_tracking_lookup.py
│   └── e2e/
│       └── test_full_order_flow.py  # Playwright
│
├── .claude/                      # Claude AI agent configuration
│   ├── agents/                   # Role-specific agent prompts
│   ├── commands/                 # Slash command definitions
│   ├── hooks/                    # Pre-commit and lint hooks
│   ├── rules/                    # Code convention rules
│   ├── skills/                   # Domain skill docs
│   └── settings.json
│
├── .github/
│   └── workflows/
│       ├── ci.yml                # Test + lint on every PR
│       └── deploy.yml            # Deploy on tag push
│
├── CLAUDE.md                     # Claude project context
├── README.md                     # This file
├── pyproject.toml                # Python project metadata + tool config
├── requirements.txt              # Pinned production deps
├── requirements-dev.txt          # Dev + test deps
├── Dockerfile
├── docker-compose.yml            # Local: app + postgres + redis
└── .env.example                  # Template — never commit .env
```

---

## 5. Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Backend API | Python 3.12 + FastAPI | Async-first, automatic OpenAPI docs, Pydantic integration |
| Frontend | React 18 + TypeScript | Component model, rich ecosystem, type safety |
| ORM | SQLAlchemy 2.x async | Full async support, explicit queries, Alembic integration |
| Migrations | Alembic | Autogenerate + version-controlled schema changes |
| Validation | Pydantic v2 | Request/response schemas, settings management |
| Cache | Redis | Sub-millisecond lookups, session store, queue broker |
| Queue | Celery + Redis | Reliable async task execution, retry logic, scheduling |
| Auth | JWT (python-jose) | Stateless, scalable, access + refresh token pattern |
| Frontend State | Zustand | Minimal, TypeScript-first, no boilerplate |
| Server State | TanStack Query | Caching, background refetch, optimistic updates |
| HTTP Client | Axios | Interceptors for auth headers + error normalization |
| Testing (API) | pytest + httpx | Async test client, fixture ecosystem |
| Testing (UI) | Vitest + RTL + msw | Co-located tests, API mocking |
| Linting | Ruff + mypy | Fast, opinionated, catches type errors at CI time |
| Containerization | Docker + docker-compose | Reproducible environments |
| CI/CD | GitHub Actions | Native GitHub integration |

---

## 6. Team Boundaries & Integrations

This service is the **Order Tracking Team**'s core system. It integrates synchronously and asynchronously with four other teams.

```
┌──────────────────────────────────────────────────────────────────────┐
│                     ORDER TRACKING TEAM (this repo)                 │
│                                                                      │
│  Owns: orders, order_items, shipments, tracking_events              │
│  Does NOT own: inventory, payments, notifications, analytics         │
└────────┬──────────────┬──────────────┬──────────────┬───────────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
  ┌────────────┐ ┌────────────┐ ┌──────────────┐ ┌──────────────┐
  │ INVENTORY  │ │  PAYMENTS  │ │NOTIFICATIONS │ │  ANALYTICS   │
  │   TEAM     │ │   TEAM     │ │    TEAM      │ │    TEAM      │
  ├────────────┤ ├────────────┤ ├──────────────┤ ├──────────────┤
  │• Reserve   │ │• Authorize │ │• Order conf. │ │• Order events│
  │  stock     │ │  charge    │ │  email       │ │  to data lake│
  │• Release   │ │• Capture   │ │• Ship alert  │ │• Status      │
  │  on cancel │ │  on ship   │ │  SMS         │ │  change logs │
  │• Check     │ │• Refund on │ │• Delivery    │ │• Revenue     │
  │  availability│ │  cancel  │ │  notification│ │  metrics     │
  └────────────┘ └────────────┘ └──────────────┘ └──────────────┘
  Sync (HTTP)    Sync (HTTP)    Async (Celery)   Async (Celery)
```

### Integration Contracts

#### Inventory Team (`app/services/inventory_service.py`)
- **Call:** `POST {INVENTORY_API_URL}/reservations`
- **When:** Order creation — before saving to DB
- **Body:** `{ "items": [{ "product_id": "...", "quantity": N }] }`
- **On failure:** Raise `HTTPException(409)` — order not created
- **On cancel:** `DELETE {INVENTORY_API_URL}/reservations/{reservation_id}`

#### Payments Team (`app/services/payment_service.py`)
- **Call:** `POST {PAYMENTS_API_URL}/authorizations`
- **When:** Order confirmation step
- **Body:** `{ "order_id": "...", "amount": "...", "customer_id": "..." }`
- **On failure:** Order stays `pending`, admin notified
- **Capture:** Called when order moves to `shipped`
- **Refund:** Called when order is `cancelled` after payment captured

#### Notifications Team (`app/workers/email_tasks.py`)
- **Transport:** Celery task → Notifications service API
- **Events:** `order.confirmed`, `order.shipped`, `order.out_for_delivery`, `order.delivered`, `order.cancelled`
- **Payload:** Order summary + customer contact details
- **Retry:** Celery auto-retries 3x with exponential backoff

#### Analytics Team (`app/workers/analytics_tasks.py`)
- **Transport:** Celery task → event stream (Kafka topic or Analytics REST API)
- **Events:** All order status changes with full context
- **Schema:** Follows Analytics Team's event schema contract (see `docs/analytics-event-schema.json`)

---

## 7. Local Development Setup

### Prerequisites

| Tool | Version | Install |
|---|---|---|
| Python | 3.12+ | [python.org](https://python.org) or `pyenv install 3.12` |
| Node.js | 20+ | [nodejs.org](https://nodejs.org) or `nvm install 20` |
| Docker Desktop | Latest | [docker.com](https://docker.com) |
| `uv` (recommended) | Latest | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |

### Step 1 — Clone the Repository

```bash
git clone https://github.com/your-org/order-tracking.git
cd order-tracking
```

### Step 2 — Start Infrastructure (PostgreSQL + Redis)

```bash
docker-compose up -d postgres redis
```

This starts:
- **PostgreSQL** on `localhost:5432` (user: `orderuser`, db: `ordertracking`)
- **Redis** on `localhost:6379`

Verify:
```bash
docker-compose ps          # both should show "Up"
docker-compose logs postgres --tail=20
```

### Step 3 — Backend Setup

```bash
# Create virtual environment and install deps
uv venv
source .venv/bin/activate       # Windows: .venv\Scripts\activate
uv sync                         # or: pip install -r requirements.txt -r requirements-dev.txt

# Copy environment variables
cp .env.example .env
# Edit .env — see Section 8 for required values

# Run database migrations
alembic upgrade head

# Seed development data
python -m app.db.seed

# Start the API server
uvicorn app.main:app --reload --port 8000
```

Verify:
- API health: http://localhost:8000/health
- Interactive docs: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### Step 4 — Start Celery Worker

In a separate terminal:
```bash
source .venv/bin/activate
celery -A app.workers worker --loglevel=info --concurrency=2
```

### Step 5 — Frontend Setup

```bash
cd frontend
npm install
npm run dev       # starts Vite dev server on http://localhost:5173
```

The frontend proxies `/api` → `http://localhost:8000` (configured in `vite.config.ts`).

### Step 6 — Verify Full Stack

```bash
# Register a customer
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "secret123"}'

# Login and grab the access token
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "secret123"}'

# Create an order (replace TOKEN)
curl -X POST http://localhost:8000/api/v1/orders \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"items": [{"product_id": "<seed-product-id>", "quantity": 2}]}'
```

---

## 8. Environment Variables

Copy `.env.example` to `.env`. **Never commit `.env`.**

```bash
# ── Database ──────────────────────────────────────────────
DATABASE_URL=postgresql+asyncpg://orderuser:orderpass@localhost:5432/ordertracking

# ── Redis ─────────────────────────────────────────────────
REDIS_URL=redis://localhost:6379/0

# ── JWT ───────────────────────────────────────────────────
JWT_SECRET=change-me-use-at-least-32-random-chars
JWT_REFRESH_SECRET=change-me-different-from-jwt-secret
JWT_ACCESS_EXPIRE_MINUTES=30
JWT_REFRESH_EXPIRE_DAYS=7

# ── Carrier Webhook ────────────────────────────────────────
CARRIER_WEBHOOK_SECRET=change-me-carrier-hmac-secret

# ── Downstream Team APIs ───────────────────────────────────
INVENTORY_API_URL=http://inventory-service/api/v1
INVENTORY_API_KEY=your-inventory-api-key

PAYMENTS_API_URL=http://payments-service/api/v1
PAYMENTS_API_KEY=your-payments-api-key

NOTIFICATIONS_API_URL=http://notifications-service/api/v1
NOTIFICATIONS_API_KEY=your-notifications-api-key

ANALYTICS_API_URL=http://analytics-service/events
ANALYTICS_API_KEY=your-analytics-api-key

# ── App Settings ───────────────────────────────────────────
APP_ENV=development              # development | staging | production
APP_DEBUG=true
CORS_ORIGINS=http://localhost:5173,http://localhost:3000
```

All values are loaded via `pydantic-settings` in `app/core/config.py` — a startup error is raised immediately if any required variable is missing.

---

## 9. Database — Schema & Migrations

### Running Migrations

```bash
# Apply all pending migrations (run on every deploy)
alembic upgrade head

# Check current migration state
alembic current

# View migration history
alembic history --verbose

# Create a new migration after changing a model
alembic revision --autogenerate -m "add_notes_column_to_orders"

# Roll back one migration
alembic downgrade -1
```

### Migration Rules
- **Never edit** an existing migration file
- Always **review** the autogenerated file before applying
- Migration file names: `snake_case` describing the change
- Test migrations locally before committing

### Seeding Development Data

```bash
python -m app.db.seed
```

Creates:
- 2 admin users
- 5 customer accounts
- 20 products with SKUs
- 10 sample orders in various statuses
- Shipments + tracking events for shipped orders

---

## 10. Backend API Deep Dive

### API Structure

All routes are mounted in `app/main.py`:
```python
app.include_router(auth_router,     prefix="/auth")
app.include_router(orders_router,   prefix="/api/v1")
app.include_router(shipments_router,prefix="/api/v1")
app.include_router(products_router, prefix="/api/v1")
app.include_router(customers_router,prefix="/api/v1")
app.include_router(tracking_router, prefix="/api/v1")
app.include_router(webhook_router,  prefix="/webhooks")
```

### Response Envelope

Every response — success or error — uses the same envelope:

```json
// Success
{
  "success": true,
  "data": { ... },
  "meta": { "page": 1, "limit": 20, "total": 100 }
}

// Error
{
  "success": false,
  "error": {
    "code": "ORDER_NOT_FOUND",
    "message": "Order ORD-20260507-00042 not found",
    "details": []
  }
}
```

### Key Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/auth/register` | Public | Create customer account |
| `POST` | `/auth/login` | Public | Get access + refresh tokens |
| `POST` | `/auth/refresh` | Refresh token | Rotate tokens |
| `GET` | `/api/v1/orders` | Customer/Admin | List orders (customer sees own; admin sees all) |
| `POST` | `/api/v1/orders` | Customer | Create order |
| `GET` | `/api/v1/orders/{id}` | Owner/Admin | Get order detail |
| `PATCH` | `/api/v1/orders/{id}/status` | Admin | Update order status |
| `POST` | `/api/v1/orders/{id}/cancel` | Owner/Admin | Cancel order |
| `GET` | `/api/v1/orders/{id}/items` | Owner/Admin | List order items |
| `GET` | `/api/v1/shipments/{id}` | Owner/Admin | Get shipment detail |
| `GET` | `/api/v1/products` | Public | List products |
| `GET` | `/api/v1/tracking/{tracking_number}` | Public | Live tracking lookup |
| `POST` | `/webhooks/carrier` | HMAC-signed | Receive carrier tracking event |

### Layer Responsibilities

```
HTTP Request
     │
     ▼
┌──────────────────────────────────────────────────┐
│  Router (app/api/v1/*.py)                        │
│  • Declare route + method                        │
│  • Apply auth dependency                         │
│  • Validate input with Pydantic schema           │
│  • Call service                                  │
│  • Return response schema                        │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│  Service (app/services/*.py)                     │
│  • Business logic and rules                      │
│  • Validate state transitions                    │
│  • Orchestrate repository calls                  │
│  • Fire Celery tasks                             │
│  • Call external team APIs                       │
│  • Raise domain exceptions                       │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│  Repository (app/repositories/*.py)              │
│  • All SQLAlchemy queries                        │
│  • Pagination with offset/limit                  │
│  • Explicit relationship loading                 │
│  • Wrap multi-step ops in session.begin()        │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
            PostgreSQL (async)
```

---

## 11. Authentication & Authorization

### Token Flow

```
1. POST /auth/login  →  { access_token, refresh_token }
2. Client stores refresh_token in httpOnly cookie
3. Client sends access_token in Authorization: Bearer header
4. Access token expires in 30 minutes
5. POST /auth/refresh (with refresh_token cookie)  →  new access_token
6. On logout: refresh token revoked in Redis
```

### JWT Payload

```json
{
  "sub": "customer-uuid",
  "email": "user@example.com",
  "role": "customer",
  "iat": 1746700000,
  "exp": 1746701800
}
```

### Role-Based Access

| Role | Can do |
|---|---|
| `customer` | Read own orders, create orders, cancel own pending orders |
| `admin` | Read all orders, update any order status, assign shipments |

Ownership check in services:
```python
if current_user.role != "admin" and order.customer_id != current_user.id:
    raise HTTPException(status_code=403, detail="FORBIDDEN")
```

---

## 12. Async Workers (Celery)

Workers are defined in `app/workers/`. The Celery app connects to Redis as both broker and result backend.

### Task Types

| Task | Trigger | Description |
|---|---|---|
| `send_order_confirmation` | Order created | Email to customer via Notifications API |
| `send_shipping_alert` | Status → `shipped` | Email + SMS to customer |
| `send_delivery_notification` | Status → `delivered` | Email to customer |
| `emit_order_event` | Any status change | Push event to Analytics Team |
| `capture_payment` | Status → `shipped` | Capture authorized charge via Payments API |
| `release_inventory` | Order cancelled | Release reservation via Inventory API |
| `refund_payment` | Cancelled after shipped | Trigger refund via Payments API |

### Starting Workers

```bash
# All queues
celery -A app.workers worker --loglevel=info

# Specific queue (separate processes in production)
celery -A app.workers worker -Q email --loglevel=info
celery -A app.workers worker -Q payments --loglevel=info

# Monitor with Flower
pip install flower
celery -A app.workers flower --port=5555
```

### Retry Policy

```python
@celery_app.task(
    bind=True,
    max_retries=3,
    default_retry_delay=60,  # seconds, doubles each retry
    autoretry_for=(requests.RequestException,),
)
def send_order_confirmation(self, order_id: str): ...
```

---

## 13. Carrier Webhook Integration

Carriers (FedEx, UPS, DHL, USPS) send `POST /webhooks/carrier` when a package status changes.

### Verification Flow

```
Carrier sends:
  POST /webhooks/carrier
  X-Carrier-Signature: sha256=<hmac_hex>
  X-Carrier-Timestamp: 1746700000

Our handler:
1. Check abs(now - timestamp) <= 300 seconds  → reject if stale (replay protection)
2. Compute HMAC-SHA256(body, CARRIER_WEBHOOK_SECRET)
3. hmac.compare_digest(computed, received)     → reject if mismatch
4. Parse body → find shipment by tracking_number
5. Create TrackingEvent
6. Update Order status if needed
7. Fire Celery tasks (notify customer, analytics)
8. Return HTTP 200
```

### Webhook Payload (Expected Shape)

```json
{
  "tracking_number": "1Z999AA10123456784",
  "carrier": "UPS",
  "status": "OUT_FOR_DELIVERY",
  "location": "Memphis, TN",
  "description": "Package is out for delivery",
  "occurred_at": "2026-05-07T09:30:00Z"
}
```

### Carrier Status → Our Status Mapping

| Carrier Status | Our Status |
|---|---|
| `PICKED_UP` | `shipped` |
| `IN_TRANSIT` | `shipped` |
| `OUT_FOR_DELIVERY` | `out_for_delivery` |
| `DELIVERED` | `delivered` |
| `DELIVERY_ATTEMPT_FAILED` | `shipped` (no state change) |

---

## 14. Frontend Architecture

### Routing Structure

```
/                     → redirect to /orders
/login                → LoginPage (public)
/track/:trackingNum   → TrackingPage (public)
/orders               → OrderListPage (auth required)
/orders/:id           → OrderDetailPage (auth required)
/admin/orders         → AdminOrderListPage (admin role required)
```

### State Architecture

```
Server State (React Query)          Global UI State (Zustand)
─────────────────────────           ─────────────────────────
useQuery(["orders"])                authStore
  ├── data: Order[]                   ├── currentUser
  ├── isLoading                       ├── accessToken
  └── error                          ├── login()
                                      └── logout()
useQuery(["order", id])
useQuery(["tracking", trackingNum])
useMutation(createOrder)
useMutation(cancelOrder)
```

### API Client (`frontend/src/api/client.ts`)

```typescript
// Request interceptor: attach access token
axios.interceptors.request.use((config) => {
  const token = authStore.getState().accessToken;
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// Response interceptor: refresh token on 401
axios.interceptors.response.use(
  (res) => res,
  async (err) => {
    if (err.response?.status === 401 && !err.config._retry) {
      err.config._retry = true;
      await authStore.getState().refresh();
      return axios(err.config);
    }
    return Promise.reject(err);
  }
);
```

---

## 15. Testing Strategy

### Test Pyramid

```
        ┌────────────────┐
        │   E2E Tests    │  ← Few, slow, high confidence
        │   (Playwright) │     Full order flow browser tests
        └───────┬────────┘
        ┌───────▼────────────────┐
        │  Integration Tests     │  ← Many, medium speed
        │  (pytest + httpx)      │     Real DB (rolled back per test)
        └───────┬────────────────┘
        ┌───────▼────────────────────────────┐
        │        Unit Tests                  │  ← Most, fast
        │  (pytest / Vitest + RTL)           │     No DB, no HTTP
        └────────────────────────────────────┘
```

### Running Tests

```bash
# All tests
pytest

# Unit tests only (fast)
pytest tests/unit/ -v

# Integration tests only
pytest tests/integration/ -v

# With coverage report
pytest --cov=app --cov-report=term-missing --cov-report=html

# Specific test
pytest tests/integration/test_create_order.py::test_create_order_returns_pending -s

# Frontend tests
cd frontend && npm test

# Frontend with coverage
cd frontend && npm run test:coverage
```

### Test Coverage Targets

| Layer | Target |
|---|---|
| Services | 90%+ |
| Repositories | 80%+ |
| Routers | 70%+ |
| Workers | 70%+ |

### Key Test Scenarios

- Order creation → happy path
- Order creation → out-of-stock (Inventory API returns 409)
- Order creation → payment failure
- Status transition → valid (all valid transitions)
- Status transition → invalid → expect 409
- Cancel order → own order (allowed)
- Cancel order → another customer's order → expect 403
- Carrier webhook → valid HMAC → TrackingEvent created
- Carrier webhook → invalid HMAC → expect 401
- Carrier webhook → replayed (stale timestamp) → expect 401
- Duplicate tracking event → idempotent (not duplicated)

---

## 16. CI/CD Pipeline

### `.github/workflows/ci.yml` — Runs on every PR

```
1. Checkout code
2. Set up Python 3.12
3. Install dependencies (uv sync)
4. Run Ruff lint check         → fail on any error
5. Run mypy type check         → fail on any error
6. Start PostgreSQL + Redis (GitHub Actions services)
7. Run Alembic migrations      → fail if migration errors
8. Run pytest with coverage    → fail if coverage drops below threshold
9. Set up Node.js 20
10. npm install (frontend)
11. npm run lint (frontend)
12. npm test (frontend)
```

### `.github/workflows/deploy.yml` — Runs on tag push (`v*`)

```
1. Run full CI suite (above)
2. Build Docker image
3. Push to container registry (GHCR)
4. SSH to staging/production server
5. Pull new image
6. Run alembic upgrade head
7. Restart Gunicorn (zero-downtime rolling restart)
8. Smoke test: GET /health must return 200
9. Notify team on success/failure (Slack webhook)
```

---

## 17. Deployment

### Docker Compose (Staging/Production Reference)

```yaml
# docker-compose.prod.yml
services:
  api:
    image: ghcr.io/your-org/order-tracking:latest
    command: gunicorn app.main:app -w 4 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000
    env_file: .env.prod
    depends_on: [postgres, redis]
    ports: ["8000:8000"]
    restart: unless-stopped

  worker:
    image: ghcr.io/your-org/order-tracking:latest
    command: celery -A app.workers worker --loglevel=info -c 4
    env_file: .env.prod
    depends_on: [postgres, redis]
    restart: unless-stopped

  postgres:
    image: postgres:16
    volumes: [pg_data:/var/lib/postgresql/data]
    environment:
      POSTGRES_USER: orderuser
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ordertracking

  redis:
    image: redis:7-alpine
    volumes: [redis_data:/data]

  nginx:
    image: nginx:alpine
    volumes: [./nginx.conf:/etc/nginx/nginx.conf:ro]
    ports: ["80:80", "443:443"]
    depends_on: [api]
```

### Zero-Downtime Deploy Steps

```bash
# 1. Pull latest image
docker pull ghcr.io/your-org/order-tracking:v1.2.3

# 2. Run migrations (before restarting app)
docker run --rm --env-file .env.prod \
  ghcr.io/your-org/order-tracking:v1.2.3 \
  alembic upgrade head

# 3. Rolling restart (Gunicorn handles in-flight requests)
docker-compose -f docker-compose.prod.yml up -d --no-deps api worker

# 4. Verify
curl https://api.ordertracking.com/health
```

### Rollback

```bash
# Redeploy previous image
docker-compose -f docker-compose.prod.yml up -d \
  --no-deps api worker \
  -e IMAGE_TAG=v1.2.2

# Roll back last migration if needed
docker run --rm --env-file .env.prod \
  ghcr.io/your-org/order-tracking:v1.2.2 \
  alembic downgrade -1
```

---

## 18. Observability — Logs, Metrics, Tracing

### Structured Logging

All logs are JSON-structured. Use Python's `structlog` or `logging` with JSON formatter:

```python
import logging
logger = logging.getLogger(__name__)

logger.info("order.created", extra={
    "order_id": order.id,
    "customer_id": order.customer_id,
    "item_count": len(order.items),
})
```

**Never log:** passwords, tokens, full credit card numbers, raw webhook bodies.

### Key Metrics to Monitor

| Metric | Alert Threshold |
|---|---|
| API `p99` latency | > 2 seconds |
| `5xx` error rate | > 1% of requests |
| Celery queue depth | > 1000 tasks |
| PostgreSQL connections | > 80% of pool |
| Order `pending` age | > 30 minutes without transition |
| Webhook failures | > 5 in 5 minutes |

### Health Endpoint

`GET /health` returns:

```json
{
  "status": "healthy",
  "checks": {
    "database": "ok",
    "redis": "ok",
    "celery": "ok"
  },
  "version": "1.2.3"
}
```

Returns `503` if any check fails — used by load balancer health probes.

---

## 19. Security Considerations

| Area | Control |
|---|---|
| Auth | JWT with short-lived access tokens (30 min) + refresh rotation |
| IDOR prevention | Service layer checks `customer_id == current_user.id` |
| Webhook spoofing | HMAC-SHA256 with `hmac.compare_digest()` + 5-minute replay window |
| SQL injection | SQLAlchemy parameterized queries — no raw string interpolation |
| Secrets | All secrets via env vars + `pydantic-settings` — no hardcoding |
| Rate limiting | Nginx `limit_req` on `/auth/` and `/webhooks/` |
| CORS | `allow_origins` restricted to known frontend domains |
| Input size | Request body max size enforced at Nginx level (1MB) |
| Dependency CVEs | `pip audit` in CI pipeline |
| `.env` protection | Listed in `.gitignore`; pre-commit hook blocks staging |
| Error messages | Internal errors sanitized before returning to client |

---

## 20. Contributing Guide

### Branching Strategy

```
main           ← production-ready, tagged for releases
staging        ← deployed to staging environment
feature/*      ← new features (branch from main)
fix/*          ← bug fixes (branch from main)
```

### Workflow

```bash
# 1. Branch from main
git checkout -b feature/add-order-notes main

# 2. Make changes following CLAUDE.md conventions

# 3. Run checks locally before pushing
pytest
ruff check .
mypy app/
cd frontend && npm test

# 4. Commit with conventional commit message
git commit -m "feat: add notes field to orders"
git commit -m "fix: prevent double-cancel raising 500 (closes #42)"

# 5. Push and open PR
git push origin feature/add-order-notes
gh pr create --title "feat: add notes field to orders" --assignee @me

# 6. PR requires:
#    - CI passing (lint + type check + tests)
#    - 1 reviewer approval
#    - No unresolved comments
```

### Conventional Commit Prefixes

| Prefix | Use for |
|---|---|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `refactor:` | Code change without behavior change |
| `test:` | Adding or updating tests |
| `docs:` | Documentation only |
| `chore:` | Build, CI, dependencies |
| `perf:` | Performance improvement |

---

## 21. Runbook — Common Incidents

### Orders stuck in `pending`

```bash
# Check if Celery worker is running
celery -A app.workers inspect active

# Check if payment webhook failed
# Look for orders with status=pending older than 30 min
python -c "
from app.db.shell import run
run('SELECT id, created_at FROM orders WHERE status=\'pending\' AND created_at < NOW() - INTERVAL \'30 minutes\'')
"

# Manually trigger confirmation (admin action via API)
curl -X PATCH http://localhost:8000/api/v1/orders/ORD-20260507-00042/status \
  -H "Authorization: Bearer ADMIN_TOKEN" \
  -d '{"status": "confirmed"}'
```

### Carrier webhook 401s

```bash
# Verify CARRIER_WEBHOOK_SECRET matches what carrier has configured
# Check recent webhook failures in logs
grep "webhook.*401\|hmac.*invalid" /var/log/ordertracking/api.log | tail -50
```

### Database connection pool exhausted

```bash
# Check active connections
psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity WHERE datname='ordertracking';"

# Restart workers (they hold long-lived connections)
docker-compose restart worker
```

### Celery queue depth too high

```bash
# Inspect queue lengths
celery -A app.workers inspect reserved

# Add more workers temporarily
docker-compose up -d --scale worker=4
```

### Rollback a bad migration

```bash
# 1. Downgrade one step
alembic downgrade -1

# 2. Verify application starts
uvicorn app.main:app --reload

# 3. Fix the migration file (create a NEW migration — never edit existing)
alembic revision --autogenerate -m "fix_<description>"
alembic upgrade head
```

---

## Quick Reference

```bash
# Start everything locally
docker-compose up -d postgres redis
source .venv/bin/activate
uvicorn app.main:app --reload &
celery -A app.workers worker --loglevel=info &
cd frontend && npm run dev

# Run all checks
pytest && ruff check . && mypy app/

# Generate + apply a new migration
alembic revision --autogenerate -m "your_change_description"
alembic upgrade head

# Interactive API docs
open http://localhost:8000/docs
```

---

*Maintained by the Order Tracking Team. For questions about downstream integrations, contact the respective team leads. For security issues, email security@your-org.com.*
