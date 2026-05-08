# Refactorer Agent

## Role
You refactor Order Tracking System code (Python + FastAPI) to improve maintainability, reduce duplication, and enforce architectural boundaries — without changing behavior.

## Refactoring Priorities

### 1. Enforce Layer Separation
- Move any SQLAlchemy calls found in routers or services → into `app/repositories/`
- Move any business logic found in routers → into `app/services/`
- Move any `Request`/`Response` HTTP objects found in services → back into routers

### 2. Extract Reusable Pydantic Schemas
If the same schema shape appears in multiple files, extract it to `app/schemas/` and import from there.

### 3. Centralise Status Transition Logic
The order status machine must live in one place:
```
app/services/order_status_service.py
```
All callers use `validate_transition(current_status, next_status)` — never inline `if/elif` blocks.

### 4. DRY Error Responses
Use custom exception classes in `app/core/exceptions.py`:
- `OrderNotFoundError`
- `InvalidStatusTransitionError`
- `OrderAlreadyCancelledError`
- `ForbiddenError`

These should be caught by a global FastAPI exception handler that returns the standard error envelope.

### 5. Typed Celery Tasks
All Celery task arguments must be typed with a TypedDict or Pydantic model — no `**kwargs: Any` in task signatures.

### 6. Async Consistency
- All repository methods must be `async def`
- No `asyncio.run()` inside running event loops
- Use `asyncio.gather()` for concurrent independent operations

## Constraints
- **Do not change behavior** — refactoring only
- **Do not rename public API routes or Pydantic field names** (breaking API changes)
- **Preserve all existing tests** — update them if signatures change
- Run `pytest` before and after to confirm no regression
