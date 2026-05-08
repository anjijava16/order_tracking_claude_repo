# Skill: API Scaffold

## Purpose
Step-by-step template for adding a new REST endpoint to the Order Tracking FastAPI backend. Follow this exactly to stay consistent with existing architecture.

## Checklist for a New Endpoint

- [ ] Pydantic schema in `app/schemas/`
- [ ] Repository method in `app/repositories/`
- [ ] Service method in `app/services/`
- [ ] Router in `app/api/v1/`
- [ ] Router mounted in `app/main.py`
- [ ] Integration test in `tests/integration/`

## Step 1 — Schema (`app/schemas/<entity>.py`)

```python
from pydantic import BaseModel, Field
from datetime import datetime

class OrderNoteCreate(BaseModel):
    note: str = Field(..., min_length=1, max_length=1000)

class OrderNoteResponse(BaseModel):
    id: str
    order_id: str
    note: str
    created_at: datetime

    model_config = {"from_attributes": True}
```

## Step 2 — Repository method (`app/repositories/order_repository.py`)

```python
async def add_note(self, order_id: str, note: str) -> OrderNote:
    obj = OrderNote(
        id=str(uuid4()),
        order_id=order_id,
        note=note,
    )
    self.session.add(obj)
    await self.session.flush()
    return obj
```

Rules:
- Use `self.session.flush()` not `self.session.commit()` — let service own the transaction
- Use `scalar_one_or_none()` for single-row reads
- Always use `.offset(skip).limit(min(limit, 100))` for lists

## Step 3 — Service method (`app/services/order_service.py`)

```python
async def add_order_note(
    self,
    order_id: str,
    payload: OrderNoteCreate,
    current_user: CurrentUser,
) -> OrderNote:
    order = await self.repo.get_by_id(order_id)
    if not order:
        raise OrderNotFoundError(order_id)
    if current_user.role != "admin" and order.customer_id != current_user.id:
        raise ForbiddenError()

    async with self.session.begin():
        note = await self.repo.add_note(order_id, payload.note)
    return note
```

Rules:
- All domain validation here — never in the router
- Wrap writes in `async with self.session.begin()`
- Raise domain exceptions from `app/core/exceptions.py` — NOT `HTTPException`

## Step 4 — Router (`app/api/v1/orders.py`)

```python
@router.post(
    "/{order_id}/notes",
    response_model=SuccessResponse[OrderNoteResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Add a note to an order",
)
async def add_order_note(
    order_id: str,
    payload: OrderNoteCreate,
    current_user: CurrentUser = Depends(get_current_user),
    service: OrderService = Depends(),
):
    note = await service.add_order_note(order_id, payload, current_user)
    return SuccessResponse(data=OrderNoteResponse.model_validate(note))
```

Rules:
- Always use `response_model=` — never return raw dicts
- Use `status.HTTP_201_CREATED` for POST, `200` for GET/PATCH
- Catch domain exceptions in the global error handler (`app/middleware/error_handler.py`) — do NOT try/except in routers

## Step 5 — Mount the router (`app/main.py`)

Only needed when adding a brand new router file. If adding to an existing router, skip.

```python
from app.api.v1.orders import router as orders_router
app.include_router(orders_router, prefix="/api/v1")
```

## Step 6 — Integration test (`tests/integration/test_order_notes.py`)

```python
@pytest.mark.asyncio
async def test_add_note_to_own_order(client, auth_headers, seed_order):
    resp = await client.post(
        f"/api/v1/orders/{seed_order.id}/notes",
        json={"note": "Please leave at door"},
        headers=auth_headers,
    )
    assert resp.status_code == 201
    assert resp.json()["success"] is True
    assert resp.json()["data"]["note"] == "Please leave at door"

@pytest.mark.asyncio
async def test_add_note_to_other_users_order_returns_403(
    client, auth_headers, other_user_order
):
    resp = await client.post(
        f"/api/v1/orders/{other_user_order.id}/notes",
        json={"note": "Hack"},
        headers=auth_headers,
    )
    assert resp.status_code == 403
```

## Response Envelope Helpers (`app/schemas/common.py`)

```python
from typing import Generic, TypeVar
from pydantic import BaseModel

T = TypeVar("T")

class SuccessResponse(BaseModel, Generic[T]):
    success: bool = True
    data: T
    meta: dict = {}

class ErrorDetail(BaseModel):
    code: str
    message: str
    details: list = []

class ErrorResponse(BaseModel):
    success: bool = False
    error: ErrorDetail
```
