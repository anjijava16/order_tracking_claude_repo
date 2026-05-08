# Order Tracking System — Full Execution & Code Generation Guide

> **Deep-dive reference** for using every component in this Claude project setup —
> agents, skills, hooks, commands, rules, and plugins — to build the complete
> backend, frontend, and deploy to AWS ECS.

---

## Table of Contents

1. [Project Activation — Load the Plugin Pack](#1-project-activation--load-the-plugin-pack)
2. [Session Bootstrap — How Hooks Fire on Startup](#2-session-bootstrap--how-hooks-fire-on-startup)
3. [Environment & Toolchain Setup](#3-environment--toolchain-setup)
4. [Backend — Phase-by-Phase Build Guide](#4-backend--phase-by-phase-build-guide)
   - 4.1 [Database Models + Migrations (db-migrations skill)](#41-database-models--migrations--db-migrations-skill)
   - 4.2 [Pydantic Schemas (api rule)](#42-pydantic-schemas--api-rule)
   - 4.3 [Repositories (database rule)](#43-repositories--database-rule)
   - 4.4 [Services + Order Flow (order-flow skill)](#44-services--order-flow--order-flow-skill)
   - 4.5 [FastAPI Routers (api-scaffold skill + api rule)](#45-fastapi-routers--api-scaffold-skill--api-rule)
   - 4.6 [Carrier Webhooks (carrier-integration skill)](#46-carrier-webhooks--carrier-integration-skill)
   - 4.7 [Auth Middleware](#47-auth-middleware)
   - 4.8 [Celery Workers](#48-celery-workers)
   - 4.9 [Main App Assembly](#49-main-app-assembly)
5. [Frontend — Phase-by-Phase Build Guide](#5-frontend--phase-by-phase-build-guide)
   - 5.1 [Project Bootstrap (frontend rule)](#51-project-bootstrap--frontend-rule)
   - 5.2 [API Client Layer](#52-api-client-layer)
   - 5.3 [Components (frontend-design skill)](#53-components--frontend-design-skill)
   - 5.4 [Pages & Routing](#54-pages--routing)
   - 5.5 [State Management](#55-state-management)
6. [Testing — Agents & Patterns](#6-testing--agents--patterns)
7. [Code Quality Gates — Hooks in Detail](#7-code-quality-gates--hooks-in-detail)
8. [Security Audit Before Release (audit command + security-auditor agent)](#8-security-audit-before-release--audit-command--security-auditor-agent)
9. [Containerisation — Docker & ECS](#9-containerisation--docker--ecs)
   - 9.1 [Backend Dockerfile](#91-backend-dockerfile)
   - 9.2 [Frontend Dockerfile (Nginx)](#92-frontend-dockerfile-nginx)
   - 9.3 [docker-compose for local parity](#93-docker-compose-for-local-parity)
   - 9.4 [AWS ECR — Push Images](#94-aws-ecr--push-images)
   - 9.5 [ECS Task Definitions](#95-ecs-task-definitions)
   - 9.6 [ECS Services + ALB](#96-ecs-services--alb)
   - 9.7 [ECS Celery Worker Task](#97-ecs-celery-worker-task)
   - 9.8 [RDS PostgreSQL & ElastiCache Redis](#98-rds-postgresql--elasticache-redis)
   - 9.9 [Secrets in AWS Secrets Manager](#99-secrets-in-aws-secrets-manager)
   - 9.10 [ECS Rolling Deploys + Alembic Migrations](#910-ecs-rolling-deploys--alembic-migrations)
10. [CI/CD — GitHub Actions Pipeline](#10-cicd--github-actions-pipeline)
11. [Day-2 Operations — Commands & Agents](#11-day-2-operations--commands--agents)
12. [Full Component Reference Map](#12-full-component-reference-map)

---

## 1. Project Activation — Load the Plugin Pack

The **Order Tracking Pack** (`plugins/order-tracking-pack/manifest.md`) bundles every
agent, skill, hook, rule, and command into a single activation step. Start every
session with:

```
"Load the order-tracking pack"
```

What that activates (from `manifest.md`):

| Component | File | Purpose |
|-----------|------|---------|
| Plugin manifest | `.claude/plugins/order-tracking-pack/manifest.md` | Master index of all tools |
| Hook: SessionStart | `.claude/hooks/SessionStart.sh` | Prints git branch, Python version, missing env vars |
| Hook: PostToolUse | `.claude/hooks/PostToolUse.sh` | Auto-lint every Python file saved |
| Hook: PreCompact | `.claude/hooks/PreCompact.sh` | Saves session state before memory compaction |
| Hook: pre-commit | `.claude/hooks/pre-commit.sh` | Blocks secrets, runs unit tests on commit |
| Hook: lint-on-save | `.claude/hooks/lint-on-save.sh` | Ruff lint+format on every Edit/Write |
| Agent: code-reviewer | `.claude/agents/code-reviewer.md` | Architecture + security review |
| Agent: debugger | `.claude/agents/debugger.md` | Runtime error diagnosis |
| Agent: security-auditor | `.claude/agents/security-auditor.md` | OWASP Top-10 audit |
| Agent: test-writer | `.claude/agents/test-writer.md` | pytest + RTL test generation |
| Agent: researcher | `.claude/agents/researcher.md` | Carrier API / payment research |
| Agent: log-analyzer | `.claude/agents/log-analyzer.md` | Production log triage |
| Agent: doc-writer | `.claude/agents/doc-writer.md` | API reference + ADR authoring |
| Agent: refactorer | `.claude/agents/refactorer.md` | Safe refactor with test coverage |
| Skill: api-scaffold | `.claude/skills/api-scaffold/SKILL.md` | FastAPI endpoint template |
| Skill: order-flow | `.claude/skills/order-flow/SKILL.md` | Order state machine |
| Skill: db-migrations | `.claude/skills/db-migrations/SKILL.md` | Alembic patterns |
| Skill: carrier-integration | `.claude/skills/carrier-integration/SKILL.md` | Webhook + polling |
| Skill: frontend-design | `.claude/skills/frontend-design/SKILL.md` | UI patterns + color tokens |
| Skill: frontend-designtouch | `.claude/skills/frontend-designtouch/SKILL.md` | Mobile touch interactions |
| Rule: api | `.claude/rules/api.md` | Route naming, response envelope |
| Rule: database | `.claude/rules/database.md` | SQLAlchemy async, repository pattern |
| Rule: frontend | `.claude/rules/frontend.md` | React + Zustand + React Query |
| Command: deploy | `.claude/commands/deploy.md` | Pre-deploy checklist + release |
| Command: audit | `.claude/commands/audit.md` | Full security + quality audit |
| Command: fix-issue | `.claude/commands/fix-issue.md` | GitHub issue → fix → PR |
| Command: pr-review | `.claude/commands/pr-review.md` | PR checklist + review comment |
| Output style: terse | `.claude/output-styles/terse.md` | Code-only output format |

---

## 2. Session Bootstrap — How Hooks Fire on Startup

When you open the project, **`SessionStart.sh`** runs automatically and prints:

```
=== Order Tracking — Session Start ===
Project root : /path/to/order_tracking_claude_repo
Git branch   : main
Python       : Python 3.12.x
Venv active  : .venv
--- Open TODO / FIXME count ---
X files with TODOs
--- Required env vars ---
  MISSING: DATABASE_URL        ← tells you what to fix before coding
  MISSING: REDIS_URL
  OK     : JWT_SECRET
=== Session ready ===
```

**Rules governed by `settings.json`:**
- Every `Edit` or `Write` fires `PostToolUse.sh` → auto-runs `ruff check --fix` + `ruff format`
- Every `Bash` command fires `pre-commit.sh` → blocks `.env` staging, detects hardcoded secrets,
  runs `pytest tests/unit/` before a commit lands
- `PreCompact.sh` writes `.claude/.session-state.md` before context is summarised, preserving
  git status, recent migrations, and open TODOs

---

## 3. Environment & Toolchain Setup

```bash
# Clone and enter project
git clone <repo-url> order_tracking_claude_repo
cd order_tracking_claude_repo

# Create virtual environment (Python 3.12)
python3.12 -m venv .venv
source .venv/bin/activate

# Install backend dependencies
pip install -r requirements.txt
# OR with uv (faster):
uv sync

# Copy env template
cp .env.example .env
# Fill in: DATABASE_URL, REDIS_URL, JWT_SECRET, JWT_REFRESH_SECRET, CARRIER_WEBHOOK_SECRET

# Start infrastructure locally
docker-compose up -d postgres redis

# Run initial migrations
alembic upgrade head

# Seed development data
python -m app.db.seed

# Verify backend starts
uvicorn app.main:app --reload
# → http://localhost:8000/docs

# Install frontend dependencies
cd frontend && npm install
npm run dev
# → http://localhost:5173
```

**Required `.env` keys** (from `CLAUDE.md`):

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | `postgresql+asyncpg://user:pass@localhost:5432/ordertracking` |
| `REDIS_URL` | `redis://localhost:6379/0` |
| `JWT_SECRET` | Access token signing secret (min 32 chars) |
| `JWT_REFRESH_SECRET` | Refresh token signing secret (different from JWT_SECRET) |
| `CARRIER_WEBHOOK_SECRET` | HMAC secret shared with carrier webhook sender |

---

## 4. Backend — Phase-by-Phase Build Guide

### 4.1 Database Models + Migrations — `db-migrations` Skill

**Skill file:** `.claude/skills/db-migrations/SKILL.md`
**Rule:** `.claude/rules/database.md`

**Invoke Claude with:**
```
"Use the db-migrations skill to scaffold all SQLAlchemy models for Customer, Order,
OrderItem, Product, Shipment, and TrackingEvent."
```

**Model conventions enforced by `database.md` rule:**

```python
# app/models/order.py
import enum
from datetime import datetime
from uuid import uuid4
from sqlalchemy import Index, String, Enum as SAEnum, ForeignKey, Numeric, Integer
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

class OrderStatus(str, enum.Enum):
    pending          = "pending"
    confirmed        = "confirmed"
    processing       = "processing"
    shipped          = "shipped"
    out_for_delivery = "out_for_delivery"
    delivered        = "delivered"
    cancelled        = "cancelled"

class Order(Base):
    __tablename__ = "orders"

    id: Mapped[str]           = mapped_column(String, primary_key=True)
    # ↑ format: ORD-YYYYMMDD-XXXXX — generated in OrderService, NOT here
    customer_id: Mapped[str]  = mapped_column(ForeignKey("customers.id"), nullable=False)
    status: Mapped[OrderStatus] = mapped_column(SAEnum(OrderStatus), nullable=False,
                                                 server_default="pending")
    total_amount: Mapped[float] = mapped_column(Numeric(10, 2), nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(nullable=True)
    # created_at / updated_at managed by SQLAlchemy — do NOT set manually
    created_at: Mapped[datetime] = mapped_column(server_default="now()")
    updated_at: Mapped[datetime] = mapped_column(server_default="now()", onupdate="now()")

    items:    Mapped[list["OrderItem"]] = relationship(back_populates="order")
    shipment: Mapped["Shipment | None"] = relationship(back_populates="order")

    __table_args__ = (
        Index("ix_orders_customer_id", "customer_id"),   # required by database.md
        Index("ix_orders_status",      "status"),        # required by database.md
    )
```

**Migration workflow (from `db-migrations` skill):**

```bash
# After editing any model:
alembic revision --autogenerate -m "add_orders_table"

# Review generated file in alembic/versions/ — check:
#   - correct table/column names
#   - enum types created before columns that use them
#   - indexes match required list in database.md

alembic upgrade head
alembic current   # confirm at head
```

**All required indexes (enforced by `database.md` rule):**
- `ix_orders_customer_id` on `orders.customer_id`
- `ix_orders_status` on `orders.status`
- `ix_shipments_tracking_number` on `shipments.tracking_number`
- `ix_tracking_events_shipment_id` on `tracking_events.shipment_id`

---

### 4.2 Pydantic Schemas — `api` Rule

**Rule file:** `.claude/rules/api.md`

**Invoke Claude with:**
```
"Following the api rule, generate Pydantic v2 schemas for Order (create/response),
OrderItem, Shipment, TrackingEvent, and the standard SuccessResponse envelope."
```

**Response envelope (mandatory for all routes):**

```python
# app/schemas/base.py
from typing import Generic, TypeVar, Any
from pydantic import BaseModel

T = TypeVar("T")

class SuccessResponse(BaseModel, Generic[T]):
    success: bool = True
    data: T
    meta: dict[str, Any] | None = None

class ErrorDetail(BaseModel):
    code: str
    message: str
    details: list[str] = []

class ErrorResponse(BaseModel):
    success: bool = False
    error: ErrorDetail
```

**Order schema example:**

```python
# app/schemas/order.py
from pydantic import BaseModel, Field
from datetime import datetime
from app.models.order import OrderStatus

class OrderItemCreate(BaseModel):
    product_id: str
    quantity: int = Field(..., gt=0)

class OrderCreate(BaseModel):
    items: list[OrderItemCreate] = Field(..., min_length=1)

class OrderItemResponse(BaseModel):
    id: str
    product_id: str
    quantity: int
    unit_price: float
    model_config = {"from_attributes": True}

class OrderResponse(BaseModel):
    id: str
    customer_id: str
    status: OrderStatus
    total_amount: float
    items: list[OrderItemResponse]
    created_at: datetime
    updated_at: datetime
    model_config = {"from_attributes": True}
```

**Error codes from `api.md` rule:**

| Code | HTTP | When |
|------|------|------|
| `VALIDATION_ERROR` | 422 | Pydantic failed |
| `UNAUTHORIZED` | 401 | Bad/missing JWT |
| `FORBIDDEN` | 403 | Right JWT, wrong owner |
| `ORDER_NOT_FOUND` | 404 | ID not in DB |
| `INVALID_STATUS_TRANSITION` | 409 | e.g., shipped → pending |
| `ORDER_ALREADY_CANCELLED` | 409 | Double-cancel |
| `INTERNAL_ERROR` | 500 | Unhandled exception |

---

### 4.3 Repositories — `database` Rule

**Rule file:** `.claude/rules/database.md`

**Invoke Claude with:**
```
"Following the database rule, generate OrderRepository with get_by_id, list_by_customer,
create_order, and update_status methods."
```

**Repository pattern (from `database.md`):**

```python
# app/repositories/order_repository.py
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from app.models.order import Order, OrderStatus

class OrderRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_by_id(self, order_id: str) -> Order | None:
        result = await self.session.execute(
            select(Order)
            .where(Order.id == order_id, Order.deleted_at.is_(None))
            .options(selectinload(Order.items), selectinload(Order.shipment))
        )
        return result.scalar_one_or_none()

    async def list_by_customer(
        self,
        customer_id: str,
        skip: int = 0,
        limit: int = 20,
    ) -> list[Order]:
        result = await self.session.execute(
            select(Order)
            .where(Order.customer_id == customer_id, Order.deleted_at.is_(None))
            .offset(skip)
            .limit(min(limit, 100))   # ← max 100 enforced by database.md rule
            .options(selectinload(Order.items))
        )
        return list(result.scalars().all())

    async def create(self, order: Order) -> Order:
        self.session.add(order)
        await self.session.flush()
        return order

    async def update_status(self, order_id: str, status: OrderStatus) -> Order | None:
        order = await self.get_by_id(order_id)
        if order:
            order.status = status
            await self.session.flush()
        return order
```

> **Key rule:** Never import `AsyncSession` directly in services or routers.
> Never call `session.commit()` in repositories — only `flush()`.
> Wrap multi-step operations in services using `async with session.begin()`.

---

### 4.4 Services + Order Flow — `order-flow` Skill

**Skill file:** `.claude/skills/order-flow/SKILL.md`

**Invoke Claude with:**
```
"Use the order-flow skill to implement OrderService with create_order,
get_order, list_orders, and transition_status methods."
```

**State machine (from `order-flow` skill):**

```
pending → confirmed → processing → shipped → out_for_delivery → delivered
    ↘         ↘            ↘
                        cancelled (from pending, confirmed, processing only)
```

**Service implementation:**

```python
# app/services/order_service.py
from datetime import date
from sqlalchemy.ext.asyncio import AsyncSession
from app.repositories.order_repository import OrderRepository
from app.core.exceptions import (
    OrderNotFoundError, ForbiddenError, InvalidStatusTransitionError
)
from app.models.order import Order, OrderStatus
from app.schemas.order import OrderCreate
from app.middleware.auth import CurrentUser
from app.workers.order_tasks import fire_transition_tasks

VALID_TRANSITIONS: dict[str, list[str]] = {
    "pending":          ["confirmed", "cancelled"],
    "confirmed":        ["processing", "cancelled"],
    "processing":       ["shipped", "cancelled"],
    "shipped":          ["out_for_delivery"],
    "out_for_delivery": ["delivered"],
    "delivered":        [],
    "cancelled":        [],
}

class OrderService:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.repo = OrderRepository(session)

    def _generate_order_id(self) -> str:
        today = date.today().strftime("%Y%m%d")
        # In production: use a DB sequence or distributed counter
        import random
        seq = random.randint(1, 99999)
        return f"ORD-{today}-{seq:05d}"

    async def create_order(
        self, customer_id: str, payload: OrderCreate
    ) -> Order:
        order_id = self._generate_order_id()
        async with self.session.begin():
            order = Order(
                id=order_id,
                customer_id=customer_id,
                status=OrderStatus.pending,
                total_amount=0.0,  # calculated after items added
            )
            return await self.repo.create(order)

    async def transition_status(
        self,
        order_id: str,
        new_status: str,
        current_user: CurrentUser,
    ) -> Order:
        order = await self.repo.get_by_id(order_id)
        if not order:
            raise OrderNotFoundError(order_id)
        if current_user.role != "admin" and order.customer_id != current_user.id:
            raise ForbiddenError()

        allowed = VALID_TRANSITIONS.get(order.status.value, [])
        if new_status not in allowed:
            raise InvalidStatusTransitionError(order.status.value, new_status)

        async with self.session.begin():
            updated = await self.repo.update_status(order_id, OrderStatus(new_status))

        await fire_transition_tasks(order_id, new_status)  # Celery side effects
        return updated
```

**Side effects per transition (from `order-flow` skill):**

| New Status | Celery Tasks |
|------------|-------------|
| `confirmed` | `send_order_confirmation`, `emit_order_event` |
| `shipped` | `send_shipping_alert`, `capture_payment`, `emit_order_event` |
| `out_for_delivery` | `send_delivery_notification`, `emit_order_event` |
| `delivered` | `send_delivery_notification`, `emit_order_event` |
| `cancelled` | `release_inventory`, `refund_payment`, `emit_order_event` |

---

### 4.5 FastAPI Routers — `api-scaffold` Skill + `api` Rule

**Skill file:** `.claude/skills/api-scaffold/SKILL.md`
**Rule file:** `.claude/rules/api.md`

**Invoke Claude with:**
```
"Use the api-scaffold skill and api rule to generate all routers:
orders, shipments, products, customers, tracking."
```

**Router pattern (from `api-scaffold` skill):**

```python
# app/api/v1/orders.py
from fastapi import APIRouter, Depends, status, Query
from app.schemas.order import OrderCreate, OrderResponse
from app.schemas.base import SuccessResponse
from app.services.order_service import OrderService
from app.middleware.auth import get_current_user, CurrentUser
from app.core.database import get_db_session
from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter(prefix="/orders", tags=["orders"])

@router.post(
    "/",
    response_model=SuccessResponse[OrderResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create a new order",
)
async def create_order(
    payload: OrderCreate,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
):
    svc = OrderService(session)
    order = await svc.create_order(current_user.id, payload)
    return SuccessResponse(data=OrderResponse.model_validate(order))

@router.get(
    "/",
    response_model=SuccessResponse[list[OrderResponse]],
    summary="List orders for the current user",
)
async def list_orders(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
):
    svc = OrderService(session)
    skip = (page - 1) * limit
    orders = await svc.list_orders(current_user.id, skip=skip, limit=limit)
    return SuccessResponse(
        data=[OrderResponse.model_validate(o) for o in orders],
        meta={"page": page, "limit": limit},
    )

@router.get(
    "/{order_id}",
    response_model=SuccessResponse[OrderResponse],
    summary="Get a single order",
)
async def get_order(
    order_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
):
    svc = OrderService(session)
    order = await svc.get_order(order_id, current_user)
    return SuccessResponse(data=OrderResponse.model_validate(order))

@router.patch(
    "/{order_id}/status",
    response_model=SuccessResponse[OrderResponse],
    summary="Transition order status",
)
async def update_order_status(
    order_id: str,
    new_status: str,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
):
    svc = OrderService(session)
    order = await svc.transition_status(order_id, new_status, current_user)
    return SuccessResponse(data=OrderResponse.model_validate(order))

@router.post(
    "/{order_id}/cancel",
    response_model=SuccessResponse[OrderResponse],
    summary="Cancel an order",
)
async def cancel_order(
    order_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
):
    svc = OrderService(session)
    order = await svc.transition_status(order_id, "cancelled", current_user)
    return SuccessResponse(data=OrderResponse.model_validate(order))
```

**All route paths (from `api.md` rule):**

| Method | Path | Auth | Handler |
|--------|------|------|---------|
| `GET` | `/api/v1/orders` | Customer/Admin | `list_orders` |
| `POST` | `/api/v1/orders` | Customer/Admin | `create_order` |
| `GET` | `/api/v1/orders/{order_id}` | Owner/Admin | `get_order` |
| `PATCH` | `/api/v1/orders/{order_id}/status` | Admin only | `update_order_status` |
| `POST` | `/api/v1/orders/{order_id}/cancel` | Owner/Admin | `cancel_order` |
| `GET` | `/api/v1/orders/{order_id}/items` | Owner/Admin | `list_order_items` |
| `GET` | `/api/v1/shipments/{shipment_id}` | Owner/Admin | `get_shipment` |
| `POST` | `/webhooks/carrier` | HMAC only | `receive_carrier_webhook` |
| `POST` | `/auth/login` | Public | `login` |
| `POST` | `/auth/refresh` | Refresh token | `refresh_token` |

---

### 4.6 Carrier Webhooks — `carrier-integration` Skill

**Skill file:** `.claude/skills/carrier-integration/SKILL.md`

**Invoke Claude with:**
```
"Use the carrier-integration skill to implement the webhook handler at
POST /webhooks/carrier with HMAC verification and idempotent event ingestion."
```

**Complete webhook handler (from skill):**

```python
# app/webhooks/carrier.py
from fastapi import APIRouter, Request, HTTPException, Depends
from sqlalchemy.ext.asyncio import AsyncSession
import hmac, hashlib, time

from app.core.config import settings
from app.core.database import get_db_session
from app.services.shipment_service import ShipmentService

router = APIRouter(prefix="/webhooks", tags=["webhooks"])

@router.post("/carrier", status_code=200)
async def receive_carrier_webhook(
    request: Request,
    session: AsyncSession = Depends(get_db_session),
):
    body = await request.body()

    # Replay attack prevention (from api.md rule: timestamp within ±5 min)
    try:
        ts = int(request.headers.get("X-Carrier-Timestamp", "0"))
    except ValueError:
        raise HTTPException(status_code=401, detail="UNAUTHORIZED")
    if abs(time.time() - ts) > 300:
        raise HTTPException(status_code=401, detail="UNAUTHORIZED")

    # HMAC-SHA256 verification (from api.md rule: always use compare_digest)
    sig_header = request.headers.get("X-Carrier-Signature", "")
    expected = "sha256=" + hmac.new(
        settings.CARRIER_WEBHOOK_SECRET.encode(),
        body,
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(expected, sig_header):
        raise HTTPException(status_code=401, detail="UNAUTHORIZED")

    payload = await request.json()
    svc = ShipmentService(session)
    await svc.ingest_carrier_event(payload)
    return {"received": True}
```

**Carrier status mapping:**

```python
# app/utils/carrier_status_map.py
CARRIER_STATUS_MAP: dict[str, str] = {
    "PU": "shipped", "IT": "shipped",       # FedEx
    "OD": "out_for_delivery", "DL": "delivered",
    "PICKUP": "shipped", "IN_TRANSIT": "shipped",  # UPS
    "OUT_FOR_DEL": "out_for_delivery", "DELIVERED": "delivered",
    "TRANSIT": "shipped", "DELIVERY": "out_for_delivery",  # DHL
}
```

---

### 4.7 Auth Middleware

```python
# app/middleware/auth.py
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from pydantic import BaseModel
from app.core.config import settings

bearer_scheme = HTTPBearer()

class CurrentUser(BaseModel):
    id: str
    email: str
    role: str  # "customer" | "admin"

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> CurrentUser:
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.JWT_SECRET,
            algorithms=["HS256"],
        )
        return CurrentUser(
            id=payload["sub"],
            email=payload["email"],
            role=payload.get("role", "customer"),
        )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "UNAUTHORIZED", "message": "Invalid or expired token"},
        )
```

---

### 4.8 Celery Workers

```python
# app/workers/order_tasks.py
from celery import shared_task

@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def send_order_confirmation(self, order_id: str):
    try:
        # send email via SES/SendGrid
        pass
    except Exception as exc:
        raise self.retry(exc=exc)

@shared_task
def emit_order_event(order_id: str, new_status: str):
    # publish to SNS/EventBridge for downstream consumers
    pass

async def fire_transition_tasks(order_id: str, new_status: str):
    task_map = {
        "confirmed":        [send_order_confirmation, emit_order_event],
        "shipped":          [send_shipping_alert, capture_payment, emit_order_event],
        "out_for_delivery": [send_delivery_notification, emit_order_event],
        "delivered":        [send_delivery_notification, emit_order_event],
        "cancelled":        [release_inventory, refund_payment, emit_order_event],
    }
    for task in task_map.get(new_status, []):
        task.delay(order_id, new_status)
```

---

### 4.9 Main App Assembly

```python
# app/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.v1 import orders, shipments, products, customers, tracking
from app.webhooks import carrier
from app.middleware.error_handler import domain_exception_handler
from app.core.config import settings

app = FastAPI(title="Order Tracking API", version="1.0.0")

# CORS — restrict to known domains (security-auditor rule)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,   # never use ["*"] in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Domain exception → HTTP response mapper
app.add_exception_handler(Exception, domain_exception_handler)

# Routers
app.include_router(orders.router,    prefix="/api/v1")
app.include_router(shipments.router, prefix="/api/v1")
app.include_router(products.router,  prefix="/api/v1")
app.include_router(customers.router, prefix="/api/v1")
app.include_router(tracking.router,  prefix="/api/v1")
app.include_router(carrier.router)   # mounts at /webhooks/carrier

@app.get("/health")
async def health():
    return {"status": "ok"}
```

---

## 5. Frontend — Phase-by-Phase Build Guide

**Rule file:** `.claude/rules/frontend.md`
**Skill files:** `.claude/skills/frontend-design/SKILL.md`, `.claude/skills/frontend-designtouch/SKILL.md`

### 5.1 Project Bootstrap — `frontend` Rule

```bash
cd frontend
npm create vite@latest . -- --template react-ts
npm install \
  zustand \
  @tanstack/react-query \
  react-router-dom \
  axios \
  tailwindcss \
  @vitejs/plugin-react
npx tailwindcss init -p
```

**File structure (from `frontend.md` rule):**
```
frontend/src/
├── api/
│   ├── client.ts         # Axios instance + auth interceptor
│   ├── orders.ts         # Order query/mutation hooks
│   ├── shipments.ts      # Shipment hooks
│   └── auth.ts           # Login/refresh hooks
├── components/
│   ├── OrderCard.tsx      # + OrderCard.test.tsx
│   ├── StatusBadge.tsx
│   ├── TrackingTimeline.tsx
│   └── OrderStatusStepper.tsx
├── pages/
│   ├── OrderListPage.tsx
│   ├── OrderDetailPage.tsx
│   └── LoginPage.tsx
├── hooks/
│   ├── useOrder.ts
│   └── useTrackingEvents.ts
├── store/
│   └── authStore.ts       # Zustand — JWT token + user
├── types/
│   └── index.ts           # Mirrors backend Pydantic schemas
└── utils/
    └── statusHelpers.ts
```

### 5.2 API Client Layer

```typescript
// frontend/src/api/client.ts
import axios from "axios";
import { useAuthStore } from "../store/authStore";

const client = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8000",
  timeout: 10_000,
});

// Attach JWT on every request
client.interceptors.request.use((config) => {
  const token = useAuthStore.getState().accessToken;
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// Map API error envelope to friendly messages
client.interceptors.response.use(
  (r) => r,
  (error) => {
    const code = error.response?.data?.error?.code;
    if (code === "UNAUTHORIZED") useAuthStore.getState().logout();
    return Promise.reject(error);
  }
);

export default client;
```

```typescript
// frontend/src/api/orders.ts
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import client from "./client";
import type { Order, OrderCreate } from "../types";

export function useOrders(page = 1, limit = 20) {
  return useQuery({
    queryKey: ["orders", page, limit],
    queryFn: () =>
      client
        .get<{ data: Order[]; meta: { total: number } }>("/api/v1/orders", {
          params: { page, limit },
        })
        .then((r) => r.data),
  });
}

export function useOrder(orderId: string) {
  return useQuery({
    queryKey: ["orders", orderId],
    queryFn: () =>
      client
        .get<{ data: Order }>(`/api/v1/orders/${orderId}`)
        .then((r) => r.data.data),
    enabled: !!orderId,
  });
}

export function useCancelOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (orderId: string) =>
      client.post(`/api/v1/orders/${orderId}/cancel`).then((r) => r.data.data),
    onSuccess: (_, orderId) => {
      qc.invalidateQueries({ queryKey: ["orders", orderId] });
      qc.invalidateQueries({ queryKey: ["orders"] });
    },
  });
}
```

### 5.3 Components — `frontend-design` Skill

**Invoke Claude with:**
```
"Use the frontend-design skill to create the StatusBadge, OrderCard,
and TrackingTimeline components with Tailwind color tokens."
```

**Status badge (color tokens from skill):**

```typescript
// frontend/src/components/StatusBadge.tsx
interface StatusBadgeProps {
  status: string;
}

const STATUS_CONFIG: Record<string, { label: string; className: string }> = {
  pending:          { label: "Pending",          className: "bg-gray-100 text-gray-700" },
  confirmed:        { label: "Confirmed",         className: "bg-blue-100 text-blue-700" },
  processing:       { label: "Processing",        className: "bg-yellow-100 text-yellow-700" },
  shipped:          { label: "Shipped",           className: "bg-purple-100 text-purple-700" },
  out_for_delivery: { label: "Out for Delivery",  className: "bg-orange-100 text-orange-700" },
  delivered:        { label: "Delivered",         className: "bg-green-100 text-green-700" },
  cancelled:        { label: "Cancelled",         className: "bg-red-100 text-red-700" },
};

export function StatusBadge({ status }: StatusBadgeProps) {
  const config = STATUS_CONFIG[status] ?? { label: status, className: "bg-gray-100 text-gray-500" };
  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${config.className}`}>
      {config.label}
    </span>
  );
}
```

**Tracking timeline (reverse-chronological):**

```typescript
// frontend/src/components/TrackingTimeline.tsx
interface TrackingEvent {
  id: string;
  status: string;
  description: string;
  location: string;
  occurred_at: string;
}

interface TrackingTimelineProps {
  events: TrackingEvent[];
}

export function TrackingTimeline({ events }: TrackingTimelineProps) {
  const sorted = [...events].sort(
    (a, b) => new Date(b.occurred_at).getTime() - new Date(a.occurred_at).getTime()
  );

  if (sorted.length === 0) {
    return (
      <p className="text-sm text-gray-500">
        Tracking info will appear once your order ships.
      </p>
    );
  }

  return (
    <ol className="relative border-l border-gray-200 ml-3">
      {sorted.map((event) => (
        <li key={event.id} className="mb-6 ml-4">
          <div className="absolute w-3 h-3 bg-blue-500 rounded-full mt-1 -left-1.5" />
          <time className="text-xs text-gray-500">
            {new Date(event.occurred_at).toLocaleString()}
          </time>
          <p className="text-sm font-medium text-gray-900 mt-0.5">
            {event.description}
          </p>
          <p className="text-xs text-gray-500">{event.location}</p>
        </li>
      ))}
    </ol>
  );
}
```

### 5.4 Pages & Routing

```typescript
// frontend/src/App.tsx
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { OrderListPage } from "./pages/OrderListPage";
import { OrderDetailPage } from "./pages/OrderDetailPage";
import { LoginPage } from "./pages/LoginPage";
import { useAuthStore } from "./store/authStore";

const qc = new QueryClient({
  defaultOptions: { queries: { staleTime: 30_000 } },
});

function PrivateRoute({ children }: { children: React.ReactNode }) {
  const isAuthenticated = !!useAuthStore((s) => s.accessToken);
  return isAuthenticated ? <>{children}</> : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <QueryClientProvider client={qc}>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/orders" element={<PrivateRoute><OrderListPage /></PrivateRoute>} />
          <Route path="/orders/:orderId" element={<PrivateRoute><OrderDetailPage /></PrivateRoute>} />
          <Route path="*" element={<Navigate to="/orders" replace />} />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
```

### 5.5 State Management

```typescript
// frontend/src/store/authStore.ts
import { create } from "zustand";
import { persist } from "zustand/middleware";

interface AuthState {
  accessToken: string | null;
  user: { id: string; email: string; role: string } | null;
  setAuth: (token: string, user: AuthState["user"]) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      accessToken: null,
      user: null,
      setAuth: (accessToken, user) => set({ accessToken, user }),
      logout: () => set({ accessToken: null, user: null }),
    }),
    { name: "auth-store" }
  )
);
```

---

## 6. Testing — Agents & Patterns

**Agent file:** `.claude/agents/test-writer.md`

**Invoke Claude with:**
```
"Use the test-writer agent to generate integration tests for POST /api/v1/orders,
covering: success (201), empty items (422), no token (401), and invalid product (404)."
```

**Integration test template (from `test-writer` agent):**

```python
# tests/integration/test_orders.py
import pytest
from httpx import AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_create_order_returns_pending(auth_headers):
    async with AsyncClient(app=app, base_url="http://test") as ac:
        r = await ac.post(
            "/api/v1/orders",
            json={"items": [{"product_id": "prod-001", "quantity": 2}]},
            headers=auth_headers,
        )
    assert r.status_code == 201
    data = r.json()["data"]
    assert data["status"] == "pending"
    assert data["id"].startswith("ORD-")

@pytest.mark.asyncio
async def test_create_order_empty_items_returns_422(auth_headers):
    async with AsyncClient(app=app, base_url="http://test") as ac:
        r = await ac.post("/api/v1/orders", json={"items": []}, headers=auth_headers)
    assert r.status_code == 422

@pytest.mark.asyncio
async def test_create_order_no_token_returns_401():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        r = await ac.post("/api/v1/orders", json={"items": []})
    assert r.status_code == 401

@pytest.mark.asyncio
async def test_cancel_order_invalid_transition(auth_headers, shipped_order):
    """Cannot cancel a shipped order."""
    async with AsyncClient(app=app, base_url="http://test") as ac:
        r = await ac.post(
            f"/api/v1/orders/{shipped_order.id}/cancel",
            headers=auth_headers,
        )
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "INVALID_STATUS_TRANSITION"
```

**Run tests:**
```bash
pytest                                 # all tests
pytest tests/unit/ -q                  # unit only (fast)
pytest tests/integration/ -v           # integration with DB
pytest --cov=app --cov-report=term-missing  # with coverage
```

**Coverage targets (from `audit.md` command):**
- Services: ≥ 90%
- Repositories: ≥ 80%
- Routers: ≥ 70%

---

## 7. Code Quality Gates — Hooks in Detail

All hooks live in `.claude/hooks/` and are wired in `settings.json`.

### Hook: `PostToolUse.sh` — fires after EVERY Python file edit
```bash
ruff check --fix "$FILE"   # auto-fix lint
ruff format "$FILE"         # format in place
```

### Hook: `lint-on-save.sh` — legacy compatibility layer
Same as PostToolUse but reads `$CLAUDE_TOOL_INPUT_FILE_PATH`.

### Hook: `pre-commit.sh` — fires before any `Bash` (git commit)
```
1. Block if .env is staged
2. Block if JWT_SECRET / DATABASE_URL appear literally in staged Python files
3. Run ruff on staged .py files
4. Run pytest tests/unit/ — commit blocked on failure
```

### Hook: `SessionStart.sh` — fires once on session open
- Prints git branch, Python version, venv status
- Lists files with TODO/FIXME
- Reports missing required env vars

### Hook: `PreCompact.sh` — fires before conversation compaction
- Writes `.claude/.session-state.md` with git status, recent migrations, open TODOs

### Manual quality commands:
```bash
ruff check .                   # lint entire project
ruff format --check .          # format check (no write)
mypy app/ --strict             # type check
pip audit                      # dependency CVE scan
pytest --cov=app               # coverage report
alembic check                  # detect missing migrations
```

---

## 8. Security Audit Before Release — `audit` Command + `security-auditor` Agent

**Command file:** `.claude/commands/audit.md`
**Agent file:** `.claude/agents/security-auditor.md`

**Run full audit:**
```
/audit
```

**Run security-only:**
```
/audit security
```

**Critical checks (from `security-auditor` agent):**

| Check | Location | Tool |
|-------|----------|------|
| All routes have `Depends(get_current_user)` | `app/api/v1/*.py` | Code review |
| No IDOR — customer only sees own orders | `app/services/*.py` | Code review |
| `hmac.compare_digest()` on webhook | `app/webhooks/carrier.py` | Code review |
| Replay attack window ≤ 5 min | `app/webhooks/carrier.py` | Code review |
| Pagination cap `min(limit, 100)` | `app/repositories/*.py` | Code review |
| No raw exceptions to client | `app/middleware/error_handler.py` | Code review |
| No PII in logs | Entire `app/` | `grep -r "email\|password" app/` |
| No secrets hardcoded | Entire `app/` | `grep -rE "SECRET\s*=" app/` |
| No CRITICAL CVEs | `requirements.txt` | `pip audit` |
| CORS restricted | `app/main.py` | Code review |

---

## 9. Containerisation — Docker & ECS

### 9.1 Backend Dockerfile

```dockerfile
# Dockerfile (backend)
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/bin /usr/local/bin
COPY app/ ./app/
COPY alembic/ ./alembic/
COPY alembic.ini .

EXPOSE 8000
CMD ["gunicorn", "app.main:app", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", "--access-logfile", "-"]
```

### 9.2 Frontend Dockerfile (Nginx)

```dockerfile
# frontend/Dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json .
RUN npm ci
COPY . .
RUN npm run build        # outputs to /app/dist

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

```nginx
# frontend/nginx.conf
server {
    listen 80;
    location / {
        root   /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;  # SPA fallback
    }
    location /api/ {
        proxy_pass http://backend-alb;    # ALB DNS for the backend ECS service
    }
}
```

### 9.3 docker-compose for Local Parity

```yaml
# docker-compose.yml
version: "3.9"
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: ordertracking
      POSTGRES_USER: orderuser
      POSTGRES_PASSWORD: devpassword
    ports: ["5432:5432"]
    volumes: [pgdata:/var/lib/postgresql/data]

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

  api:
    build: .
    depends_on: [postgres, redis]
    environment:
      DATABASE_URL: postgresql+asyncpg://orderuser:devpassword@postgres:5432/ordertracking
      REDIS_URL: redis://redis:6379/0
      JWT_SECRET: ${JWT_SECRET}
      JWT_REFRESH_SECRET: ${JWT_REFRESH_SECRET}
      CARRIER_WEBHOOK_SECRET: ${CARRIER_WEBHOOK_SECRET}
    ports: ["8000:8000"]

  worker:
    build: .
    command: celery -A app.workers worker --loglevel=info
    depends_on: [postgres, redis]
    environment:
      DATABASE_URL: postgresql+asyncpg://orderuser:devpassword@postgres:5432/ordertracking
      REDIS_URL: redis://redis:6379/0

  frontend:
    build: ./frontend
    ports: ["80:80"]
    depends_on: [api]

volumes:
  pgdata:
```

### 9.4 AWS ECR — Push Images

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    <account_id>.dkr.ecr.us-east-1.amazonaws.com

# Create repositories (once)
aws ecr create-repository --repository-name order-tracking/api
aws ecr create-repository --repository-name order-tracking/frontend
aws ecr create-repository --repository-name order-tracking/worker

# Tag and push backend API image
docker build -t order-tracking-api .
docker tag order-tracking-api:latest \
  <account_id>.dkr.ecr.us-east-1.amazonaws.com/order-tracking/api:latest
docker push <account_id>.dkr.ecr.us-east-1.amazonaws.com/order-tracking/api:latest

# Tag and push frontend image
docker build -t order-tracking-frontend ./frontend
docker tag order-tracking-frontend:latest \
  <account_id>.dkr.ecr.us-east-1.amazonaws.com/order-tracking/frontend:latest
docker push <account_id>.dkr.ecr.us-east-1.amazonaws.com/order-tracking/frontend:latest

# Tag and push Celery worker (same base image as API, different CMD)
docker tag order-tracking-api:latest \
  <account_id>.dkr.ecr.us-east-1.amazonaws.com/order-tracking/worker:latest
docker push <account_id>.dkr.ecr.us-east-1.amazonaws.com/order-tracking/worker:latest
```

### 9.5 ECS Task Definitions

**Backend API task definition (`api-task-def.json`):**

```json
{
  "family": "order-tracking-api",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::<account>:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::<account>:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "api",
      "image": "<account_id>.dkr.ecr.us-east-1.amazonaws.com/order-tracking/api:latest",
      "portMappings": [{ "containerPort": 8000, "protocol": "tcp" }],
      "essential": true,
      "environment": [
        { "name": "ALLOWED_ORIGINS", "value": "https://app.ordertracking.com" }
      ],
      "secrets": [
        { "name": "DATABASE_URL",            "valueFrom": "arn:aws:secretsmanager:...:DATABASE_URL" },
        { "name": "REDIS_URL",               "valueFrom": "arn:aws:secretsmanager:...:REDIS_URL" },
        { "name": "JWT_SECRET",              "valueFrom": "arn:aws:secretsmanager:...:JWT_SECRET" },
        { "name": "JWT_REFRESH_SECRET",      "valueFrom": "arn:aws:secretsmanager:...:JWT_REFRESH_SECRET" },
        { "name": "CARRIER_WEBHOOK_SECRET",  "valueFrom": "arn:aws:secretsmanager:...:CARRIER_WEBHOOK_SECRET" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/order-tracking-api",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

**Register the task definition:**
```bash
aws ecs register-task-definition --cli-input-json file://api-task-def.json
```

**Frontend task definition (`frontend-task-def.json`):**

```json
{
  "family": "order-tracking-frontend",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::<account>:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "frontend",
      "image": "<account_id>.dkr.ecr.us-east-1.amazonaws.com/order-tracking/frontend:latest",
      "portMappings": [{ "containerPort": 80, "protocol": "tcp" }],
      "essential": true,
      "environment": [
        { "name": "VITE_API_BASE_URL", "value": "https://api.ordertracking.com" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/order-tracking-frontend",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

**Celery worker task definition (`worker-task-def.json`):**

```json
{
  "family": "order-tracking-worker",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::<account>:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "worker",
      "image": "<account_id>.dkr.ecr.us-east-1.amazonaws.com/order-tracking/worker:latest",
      "command": ["celery", "-A", "app.workers", "worker", "--loglevel=info"],
      "essential": true,
      "secrets": [
        { "name": "DATABASE_URL",           "valueFrom": "arn:aws:secretsmanager:...:DATABASE_URL" },
        { "name": "REDIS_URL",              "valueFrom": "arn:aws:secretsmanager:...:REDIS_URL" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/order-tracking-worker",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

### 9.6 ECS Services + ALB

```bash
# Create ECS Cluster
aws ecs create-cluster --cluster-name order-tracking

# Create Application Load Balancers (one per service or shared with path routing)
aws elbv2 create-load-balancer \
  --name order-tracking-alb \
  --subnets subnet-aaa subnet-bbb \
  --security-groups sg-alb

# Create Target Groups
aws elbv2 create-target-group \
  --name api-tg \
  --protocol HTTP \
  --port 8000 \
  --vpc-id vpc-xxxx \
  --target-type ip \
  --health-check-path /health

aws elbv2 create-target-group \
  --name frontend-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-xxxx \
  --target-type ip \
  --health-check-path /

# Create Listener with path-based routing
# /api/* → api-tg     (port 443 with ACM cert for HTTPS)
# /*     → frontend-tg

# Create API ECS Service
aws ecs create-service \
  --cluster order-tracking \
  --service-name api \
  --task-definition order-tracking-api:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[subnet-private-aaa,subnet-private-bbb],
    securityGroups=[sg-api],
    assignPublicIp=DISABLED
  }" \
  --load-balancers "targetGroupArn=arn:aws:elasticloadbalancing:...:api-tg,
    containerName=api,containerPort=8000" \
  --deployment-configuration "minimumHealthyPercent=100,maximumPercent=200"

# Create Frontend ECS Service
aws ecs create-service \
  --cluster order-tracking \
  --service-name frontend \
  --task-definition order-tracking-frontend:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[subnet-private-aaa,subnet-private-bbb],
    securityGroups=[sg-frontend],
    assignPublicIp=DISABLED
  }" \
  --load-balancers "targetGroupArn=arn:aws:elasticloadbalancing:...:frontend-tg,
    containerName=frontend,containerPort=80"
```

### 9.7 ECS Celery Worker Task

```bash
# Celery worker runs as a long-running ECS service (no ALB needed)
aws ecs create-service \
  --cluster order-tracking \
  --service-name celery-worker \
  --task-definition order-tracking-worker:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[subnet-private-aaa,subnet-private-bbb],
    securityGroups=[sg-worker],
    assignPublicIp=DISABLED
  }"
```

### 9.8 RDS PostgreSQL & ElastiCache Redis

```bash
# RDS PostgreSQL 16 (Multi-AZ for production)
aws rds create-db-instance \
  --db-instance-identifier order-tracking-db \
  --db-instance-class db.t4g.medium \
  --engine postgres \
  --engine-version 16.2 \
  --master-username orderadmin \
  --master-user-password "$(openssl rand -base64 24)" \
  --allocated-storage 20 \
  --multi-az \
  --vpc-security-group-ids sg-rds \
  --db-subnet-group-name order-tracking-db-subnet-group \
  --backup-retention-period 7 \
  --storage-encrypted

# ElastiCache Redis 7 (cluster mode for HA)
aws elasticache create-replication-group \
  --replication-group-id order-tracking-cache \
  --description "Order tracking Redis" \
  --num-cache-clusters 2 \
  --cache-node-type cache.t4g.small \
  --engine redis \
  --engine-version 7.0 \
  --security-group-ids sg-redis \
  --cache-subnet-group-name order-tracking-cache-subnet
```

### 9.9 Secrets in AWS Secrets Manager

```bash
# Store all required secrets (from CLAUDE.md env vars)
aws secretsmanager create-secret \
  --name /order-tracking/production/DATABASE_URL \
  --secret-string "postgresql+asyncpg://orderadmin:pass@rds-endpoint:5432/ordertracking"

aws secretsmanager create-secret \
  --name /order-tracking/production/REDIS_URL \
  --secret-string "redis://elasticache-endpoint:6379/0"

aws secretsmanager create-secret \
  --name /order-tracking/production/JWT_SECRET \
  --secret-string "$(openssl rand -hex 32)"

aws secretsmanager create-secret \
  --name /order-tracking/production/JWT_REFRESH_SECRET \
  --secret-string "$(openssl rand -hex 32)"

aws secretsmanager create-secret \
  --name /order-tracking/production/CARRIER_WEBHOOK_SECRET \
  --secret-string "$(openssl rand -hex 32)"

# IAM policy to allow ECS task role to read secrets
# Attach this policy to the ecsTaskRole:
# {
#   "Effect": "Allow",
#   "Action": ["secretsmanager:GetSecretValue"],
#   "Resource": "arn:aws:secretsmanager:us-east-1:<account>:secret:/order-tracking/production/*"
# }
```

### 9.10 ECS Rolling Deploys + Alembic Migrations

**Migration must run BEFORE the new task replaces old tasks. Use an ECS one-off task:**

```bash
# Step 1: Build and push new images (CI does this)
docker build -t order-tracking-api:v1.2.0 .
docker tag order-tracking-api:v1.2.0 <ecr>/order-tracking/api:v1.2.0
docker push <ecr>/order-tracking/api:v1.2.0

# Step 2: Run Alembic migration as a one-off ECS task BEFORE deploying the new service
aws ecs run-task \
  --cluster order-tracking \
  --task-definition order-tracking-api:latest \
  --launch-type FARGATE \
  --overrides '{"containerOverrides":[{
    "name":"api",
    "command":["alembic","upgrade","head"]
  }]}' \
  --network-configuration "awsvpcConfiguration={
    subnets=[subnet-private-aaa],
    securityGroups=[sg-api],
    assignPublicIp=DISABLED
  }"

# Wait for migration task to complete
aws ecs wait tasks-stopped --cluster order-tracking --tasks <task-arn>

# Step 3: Update ECS services to new image (rolling update, minimumHealthyPercent=100)
aws ecs update-service \
  --cluster order-tracking \
  --service api \
  --task-definition order-tracking-api:latest \
  --force-new-deployment

aws ecs update-service \
  --cluster order-tracking \
  --service celery-worker \
  --task-definition order-tracking-worker:latest \
  --force-new-deployment
```

**Rollback:**
```bash
# Redeploy previous task definition revision
aws ecs update-service \
  --cluster order-tracking \
  --service api \
  --task-definition order-tracking-api:<previous-revision>

# Roll back DB migration
aws ecs run-task \
  --cluster order-tracking \
  --task-definition order-tracking-api:<previous-revision> \
  --overrides '{"containerOverrides":[{"name":"api","command":["alembic","downgrade","-1"]}]}' \
  ...
```

---

## 10. CI/CD — GitHub Actions Pipeline

**Triggered by:** push to `main` (staging) or version tag `v*` (production).

```yaml
# .github/workflows/deploy.yml
name: Build, Test & Deploy

on:
  push:
    branches: [main]
    tags: ["v*"]

env:
  AWS_REGION: us-east-1
  ECR_REGISTRY: <account_id>.dkr.ecr.us-east-1.amazonaws.com

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_PASSWORD: test, POSTGRES_DB: ordertracking_test }
        options: --health-cmd pg_isready
      redis:
        image: redis:7
        options: --health-cmd "redis-cli ping"
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install -r requirements.txt
      - run: ruff check .
      - run: mypy app/
      - run: pytest --cov=app --cov-report=xml
        env:
          DATABASE_URL: postgresql+asyncpg://postgres:test@localhost:5432/ordertracking_test
          REDIS_URL: redis://localhost:6379/0
          JWT_SECRET: test-secret-32-chars-xxxxxxxxxx
          JWT_REFRESH_SECRET: test-refresh-secret-32-chars-xxxx
          CARRIER_WEBHOOK_SECRET: test-carrier-secret

  build-push:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      - uses: aws-actions/amazon-ecr-login@v2
      - name: Build and push API image
        run: |
          docker build -t $ECR_REGISTRY/order-tracking/api:${{ github.sha }} .
          docker push $ECR_REGISTRY/order-tracking/api:${{ github.sha }}
      - name: Build and push Frontend image
        run: |
          docker build -t $ECR_REGISTRY/order-tracking/frontend:${{ github.sha }} ./frontend
          docker push $ECR_REGISTRY/order-tracking/frontend:${{ github.sha }}

  deploy-staging:
    needs: build-push
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - name: Run DB migrations
        run: |
          aws ecs run-task \
            --cluster order-tracking-staging \
            --task-definition order-tracking-api \
            --overrides "{\"containerOverrides\":[{\"name\":\"api\",
              \"command\":[\"alembic\",\"upgrade\",\"head\"],
              \"environment\":[{\"name\":\"IMAGE_TAG\",\"value\":\"${{ github.sha }}\"}]}]}" \
            --launch-type FARGATE \
            --network-configuration "..."
      - name: Deploy API service
        run: |
          aws ecs update-service \
            --cluster order-tracking-staging \
            --service api \
            --force-new-deployment
      - name: Run smoke tests
        run: pytest tests/smoke/ --base-url=${{ vars.STAGING_API_URL }}

  deploy-production:
    needs: build-push
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    environment: production
    steps:
      # Same as staging but targets production cluster
      - name: Run DB migrations (production)
        run: |
          aws ecs run-task --cluster order-tracking ...
      - name: Deploy all services
        run: |
          aws ecs update-service --cluster order-tracking --service api --force-new-deployment
          aws ecs update-service --cluster order-tracking --service frontend --force-new-deployment
          aws ecs update-service --cluster order-tracking --service celery-worker --force-new-deployment
      - name: Verify health
        run: curl -f https://api.ordertracking.com/health
```

---

## 11. Day-2 Operations — Commands & Agents

### Fix a Production Bug
```
/fix-issue 42
```
Workflow (from `fix-issue.md` command):
1. `gh issue view 42` — read issue
2. Identify layer (router / service / repository / frontend)
3. `pytest tests/ -k <keyword> -s -v` — reproduce
4. Implement fix in correct layer
5. Add/update tests
6. `git checkout -b fix/issue-42-order-status-bug`
7. `git commit -m "fix: correct status transition guard (closes #42)"`
8. `gh pr create --title "fix: ..."` — open PR

### Review a Pull Request
```
/pr-review 87
```
Workflow (from `pr-review.md` command): fetches PR diff, runs architecture + security checklist, posts review comment via `gh pr review`.

### Diagnose Production Errors
```
"Invoke the log-analyzer agent with these logs: [paste logs]"
```
The `log-analyzer` agent (`.claude/agents/log-analyzer.md`) matches log patterns to known root causes and produces a fix + prevention recommendation.

### Carrier API Research
```
"Invoke the researcher agent to summarize FedEx webhook integration patterns."
```

### Debug a Runtime Error
```
"Invoke the debugger agent — I'm getting MissingGreenlet errors on the order detail page."
```
The `debugger` agent diagnoses by layer and produces: Root Cause → Fix → Prevention.

### Write API Documentation
```
"Invoke the doc-writer agent to write the API reference for POST /api/v1/orders."
```

---

## 12. Full Component Reference Map

```
order_tracking_claude_repo/
│
├── CLAUDE.md                        ← Project conventions, tech stack, commands
├── CLAUDE.local.md                  ← Personal overrides (gitignored)
├── settings.json                    ← Permissions allow/deny + hook wiring
│
├── .claude/
│   ├── plugins/
│   │   └── order-tracking-pack/
│   │       └── manifest.md          ← "Load the order-tracking pack" entry point
│   │
│   ├── agents/                      ← Sub-agents with specialized roles
│   │   ├── code-reviewer.md         → Invoke: "Review this PR with the code-reviewer agent"
│   │   ├── debugger.md              → Invoke: "Debug this error with the debugger agent"
│   │   ├── doc-writer.md            → Invoke: "Write API docs with the doc-writer agent"
│   │   ├── log-analyzer.md          → Invoke: "Analyze these logs with log-analyzer"
│   │   ├── refactorer.md            → Invoke: "Refactor this service safely"
│   │   ├── researcher.md            → Invoke: "Research FedEx webhooks"
│   │   ├── security-auditor.md      → Invoke: "/audit security"
│   │   └── test-writer.md           → Invoke: "Write tests for OrderService"
│   │
│   ├── commands/                    ← Slash-commands for workflows
│   │   ├── audit.md                 → /audit [security|quality|deps]
│   │   ├── deploy.md                → /deploy [staging|production]
│   │   ├── fix-issue.md             → /fix-issue <number>
│   │   └── pr-review.md             → /pr-review <number>
│   │
│   ├── hooks/                       ← Auto-executed shell scripts
│   │   ├── SessionStart.sh          → Fires on session open
│   │   ├── PostToolUse.sh           → Fires after every Edit/Write (ruff)
│   │   ├── lint-on-save.sh          → Fires on Edit/Write (legacy)
│   │   ├── pre-commit.sh            → Fires before Bash/git commit
│   │   └── PreCompact.sh            → Fires before context compaction
│   │
│   ├── skills/                      ← Domain-specific code templates
│   │   ├── api-scaffold/SKILL.md    → Schema → Repo → Service → Router pattern
│   │   ├── carrier-integration/     → HMAC webhook + idempotent ingestion
│   │   ├── db-migrations/           → Alembic patterns (add col, enum, index)
│   │   ├── frontend-design/         → UI patterns + status color tokens
│   │   ├── frontend-designtouch/    → Mobile touch interactions
│   │   └── order-flow/SKILL.md      → State machine transitions + side effects
│   │
│   ├── rules/                       ← Always-active coding standards
│   │   ├── api.md                   → Route naming, response envelope, error codes
│   │   ├── database.md              → SQLAlchemy async, repository pattern, indexes
│   │   └── frontend.md              → React/TS, Zustand, React Query, Axios
│   │
│   └── output-styles/
│       └── terse.md                 → Code-only output format
│
├── app/                             ← FastAPI backend (to be generated)
│   ├── api/v1/                      → Routers (orders, shipments, products...)
│   ├── webhooks/                    → carrier.py — HMAC-verified webhook
│   ├── services/                    → Business logic (no HTTP, no DB)
│   ├── repositories/                → All SQLAlchemy queries
│   ├── workers/                     → Celery tasks
│   ├── middleware/                  → Auth, error handler
│   ├── schemas/                     → Pydantic v2 models
│   ├── models/                      → SQLAlchemy ORM
│   └── core/                        → Config, database session, exceptions
│
├── alembic/versions/                ← Migration files (never edit existing)
│
└── frontend/src/                    ← React 18 + TypeScript frontend
    ├── api/                         → Typed Axios client + React Query hooks
    ├── components/                  → Reusable UI (StatusBadge, OrderCard...)
    ├── pages/                       → Route-level pages
    ├── store/                       → Zustand (authStore)
    ├── hooks/                       → useOrder, useTrackingEvents
    └── types/                       → TypeScript interfaces mirroring Pydantic schemas
```

---

> **Quick-start one-liner** — say this at the beginning of any Claude session:
> ```
> "Load the order-tracking pack, then scaffold the entire backend starting with
>  the database models using the db-migrations skill."
> ```
> Claude will activate all agents, skills, hooks, rules, and commands, then begin
> generating production-ready code following every convention in this guide.
