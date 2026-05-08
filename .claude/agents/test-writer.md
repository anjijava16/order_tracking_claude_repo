# Test Writer Agent

## Role
You write comprehensive tests for the Order Tracking System using pytest + httpx AsyncClient (API) and Vitest + React Testing Library (frontend).

## Test Structure
```
tests/
├── unit/          # Pure service & util logic — no DB, no HTTP
├── integration/   # API routes with real DB (rolled back per test)
└── e2e/           # Full user flows (Playwright)
```

## Integration Test Template
```python
# tests/integration/test_create_order.py
import pytest
from httpx import AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_create_order_returns_pending(auth_headers, db_session):
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post(
            "/api/v1/orders",
            json={"items": [{"product_id": "prod-001", "quantity": 2}]},
            headers=auth_headers,
        )
    assert response.status_code == 201
    data = response.json()["data"]
    assert data["status"] == "pending"
    assert data["id"].startswith("ORD-")

@pytest.mark.asyncio
async def test_create_order_empty_items_returns_422(auth_headers):
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post(
            "/api/v1/orders",
            json={"items": []},
            headers=auth_headers,
        )
    assert response.status_code == 422

@pytest.mark.asyncio
async def test_create_order_no_token_returns_401():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post("/api/v1/orders", json={"items": []})
    assert response.status_code == 401
```

## Service Unit Test Template
```python
# tests/unit/test_order_status_service.py
import pytest
from app.services.order_status_service import validate_transition
from app.core.exceptions import InvalidStatusTransitionError

@pytest.mark.parametrize("from_status,to_status", [
    ("pending", "confirmed"),
    ("confirmed", "processing"),
    ("processing", "shipped"),
    ("shipped", "out_for_delivery"),
    ("out_for_delivery", "delivered"),
])
def test_valid_transitions(from_status, to_status):
    validate_transition(from_status, to_status)  # should not raise

def test_invalid_transition_raises():
    with pytest.raises(InvalidStatusTransitionError):
        validate_transition("delivered", "pending")
```

## conftest.py Fixtures
```python
# tests/conftest.py
import pytest_asyncio
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession

@pytest_asyncio.fixture
async def db_session():
    # Create a transaction, yield session, rollback after test
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        async with AsyncSession(conn) as session:
            yield session
            await session.rollback()

@pytest.fixture
def auth_headers(test_customer_token):
    return {"Authorization": f"Bearer {test_customer_token}"}
```

## What to Test Per Feature
- **Happy path** — correct inputs, expected output
- **Validation errors** — missing fields, wrong types, invalid IDs (422)
- **Auth errors** — missing token (401), wrong role (403), other customer's order (403)
- **State machine edges** — invalid transitions, already-cancelled orders (409)
- **Idempotency** — duplicate webhook events must not create duplicate TrackingEvents

## Coverage Targets
- Services: 90%+
- Repositories: 80%+
- Routers: 70%+
