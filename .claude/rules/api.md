# API Design Rules

## Base URL
All REST endpoints: `/api/v1/`
Webhook callbacks: `/webhooks/`
Auth: `/auth/`

## Route Naming Conventions
- Use **plural nouns** for resources: `/orders`, `/shipments`, `/products`
- Nested resources use parent path: `/orders/{order_id}/items`, `/orders/{order_id}/shipments`
- No verbs in paths — use HTTP methods to express action

| Action | Method | Path |
|---|---|---|
| List orders | `GET` | `/api/v1/orders` |
| Get one order | `GET` | `/api/v1/orders/{order_id}` |
| Create order | `POST` | `/api/v1/orders` |
| Update order status | `PATCH` | `/api/v1/orders/{order_id}/status` |
| Cancel order | `POST` | `/api/v1/orders/{order_id}/cancel` |
| List order items | `GET` | `/api/v1/orders/{order_id}/items` |
| Get shipment | `GET` | `/api/v1/shipments/{shipment_id}` |
| Add tracking event | `POST` | `/webhooks/carrier` |

## FastAPI Router Structure
Each domain lives in its own router file under `app/api/v1/`:
```python
# app/api/v1/orders.py
from fastapi import APIRouter, Depends, status
from app.schemas.order import OrderCreate, OrderResponse
from app.services.order_service import OrderService
from app.middleware.auth import get_current_user

router = APIRouter(prefix="/orders", tags=["orders"])

@router.post(
    "/",
    response_model=OrderResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new order",
)
async def create_order(
    payload: OrderCreate,
    current_user=Depends(get_current_user),
    service: OrderService = Depends(),
):
    return await service.create_order(current_user.id, payload)
```

## Response Envelope
All API responses use a consistent shape via Pydantic schemas:

**Success:**
```json
{
  "success": true,
  "data": { ... },
  "meta": { "page": 1, "limit": 20, "total": 100 }
}
```

**Error:**
```json
{
  "success": false,
  "error": {
    "code": "ORDER_NOT_FOUND",
    "message": "Order ORD-20260507-00042 not found",
    "details": []
  }
}
```

## Error Codes
| Code | HTTP Status | Meaning |
|---|---|---|
| `VALIDATION_ERROR` | 422 | Pydantic validation failed |
| `UNAUTHORIZED` | 401 | Missing or invalid JWT |
| `FORBIDDEN` | 403 | Valid JWT but wrong role/owner |
| `ORDER_NOT_FOUND` | 404 | Order ID not found |
| `INVALID_STATUS_TRANSITION` | 409 | e.g., shipped → pending |
| `ORDER_ALREADY_CANCELLED` | 409 | Double-cancel attempt |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

## Validation
- All request/response models use **Pydantic v2 `BaseModel`** defined in `app/schemas/`
- FastAPI validates request bodies automatically — raise `HTTPException` for domain errors
- Pagination: `?page=1&limit=20` (max limit: 100 — enforced server-side with `min(limit, 100)`)

## Auth
- Protected routes use `Depends(get_current_user)` from `app/middleware/auth.py`
- `get_current_user` decodes JWT and returns `CurrentUser(id, email, role)`
- Customers can only access their own orders — check `current_user.id == order.customer_id`
- Raise `HTTPException(status_code=403)` for ownership violations

## Webhook Security
- Carrier webhooks at `POST /webhooks/carrier` must verify HMAC-SHA256 signature
- Signature header: `X-Carrier-Signature: sha256=<hex>`
- Use `hmac.compare_digest()` — never plain `==` for signature comparison
- Reject with `HTTPException(status_code=401)` if signature invalid or timestamp > 5 minutes old
