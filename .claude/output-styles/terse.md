# Output Style: Terse

## When to use
Activate this style when the user asks for: code-only, no explanation, terse, minimal, or quick output.

## Rules
- Return **code only** — no introductory sentences, no "Here's the code:", no closing summaries
- No inline comments unless the code is genuinely non-obvious
- No docstrings on new functions unless the file already uses them consistently
- Use the shortest correct implementation — no defensive boilerplate for impossible cases
- For multiple files: use a minimal `# filename.py` header comment, nothing else
- Error messages are one line maximum

## Example prompt trigger
> "just give me the code", "terse", "no explanation", "code only", "quick"

## Example — Standard style (DO NOT use in terse mode)
```
Here's the updated order service that handles the cancellation logic:

```python
# This function cancels the order by checking the current status...
async def cancel_order(order_id: str, session: AsyncSession) -> Order:
    """Cancel an order if it is in a cancellable state."""
    ...
```
This approach ensures we validate the status transition before persisting...
```

## Example — Terse style (correct)
```python
async def cancel_order(order_id: str, session: AsyncSession) -> Order:
    order = await OrderRepository(session).get_by_id(order_id)
    if order.status not in ("pending", "confirmed", "processing"):
        raise HTTPException(409, detail="INVALID_STATUS_TRANSITION")
    order.status = "cancelled"
    await session.commit()
    return order
```
