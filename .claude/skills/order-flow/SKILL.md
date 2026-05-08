# Skill: Order Flow

## Purpose
Reference for the Order status state machine — valid transitions, guard conditions, error codes, and service-layer implementation patterns.

## State Machine

```
pending → confirmed → processing → shipped → out_for_delivery → delivered
    ↘         ↘            ↘
                        cancelled (from pending, confirmed, processing only)
```

## Valid Transitions

```python
VALID_TRANSITIONS: dict[str, list[str]] = {
    "pending":          ["confirmed", "cancelled"],
    "confirmed":        ["processing", "cancelled"],
    "processing":       ["shipped", "cancelled"],
    "shipped":          ["out_for_delivery"],
    "out_for_delivery": ["delivered"],
    "delivered":        [],   # terminal
    "cancelled":        [],   # terminal
}
```

## Service Implementation Pattern

```python
# app/services/order_status_service.py
from app.core.exceptions import InvalidStatusTransitionError

VALID_TRANSITIONS = { ... }  # as above

def validate_transition(current: str, new: str) -> None:
    allowed = VALID_TRANSITIONS.get(current, [])
    if new not in allowed:
        raise InvalidStatusTransitionError(
            f"Cannot transition from '{current}' to '{new}'"
        )

async def transition_order(
    order_id: str,
    new_status: str,
    session: AsyncSession,
    current_user: CurrentUser,
) -> Order:
    order = await OrderRepository(session).get_by_id(order_id)
    if not order:
        raise OrderNotFoundError(order_id)

    # Ownership / role check
    if current_user.role != "admin" and order.customer_id != current_user.id:
        raise ForbiddenError()

    validate_transition(order.status, new_status)
    order.status = new_status
    await session.commit()
    return order
```

## HTTP Error Codes

| Scenario | HTTP | Error code |
|---|---|---|
| Invalid transition | 409 | `INVALID_STATUS_TRANSITION` |
| Order not found | 404 | `ORDER_NOT_FOUND` |
| Already cancelled | 409 | `ORDER_ALREADY_CANCELLED` |
| Forbidden | 403 | `FORBIDDEN` |

## Who can trigger each transition

| Transition | Customer | Admin | Carrier webhook |
|---|---|---|---|
| pending → confirmed | ❌ | ✅ | ✅ (payment webhook) |
| pending → cancelled | ✅ (own order) | ✅ | ❌ |
| confirmed → processing | ❌ | ✅ | ❌ |
| confirmed → cancelled | ❌ | ✅ | ❌ |
| processing → shipped | ❌ | ✅ | ✅ |
| processing → cancelled | ❌ | ✅ | ❌ |
| shipped → out_for_delivery | ❌ | ❌ | ✅ |
| out_for_delivery → delivered | ❌ | ❌ | ✅ |

## Side Effects on Transition

| New status | Celery tasks fired |
|---|---|
| `confirmed` | `send_order_confirmation`, `emit_order_event` |
| `shipped` | `send_shipping_alert`, `capture_payment`, `emit_order_event` |
| `out_for_delivery` | `send_delivery_notification`, `emit_order_event` |
| `delivered` | `send_delivery_notification`, `emit_order_event` |
| `cancelled` | `release_inventory`, `refund_payment` (if captured), `emit_order_event` |
