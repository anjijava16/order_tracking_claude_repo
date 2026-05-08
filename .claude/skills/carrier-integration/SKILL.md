# Skill: Carrier Integration

## Purpose
Patterns for integrating carrier webhooks and tracking APIs into the Order Tracking system. Covers HMAC verification, tracking event ingestion, idempotency, and carrier-to-internal status mapping.

## Supported Carriers

| Carrier | Webhook support | Polling fallback | Python SDK |
|---|---|---|---|
| FedEx | ✅ | ✅ | `fedex-sdk` |
| UPS | ✅ | ✅ | `ups-api-client` |
| DHL | ✅ | ✅ | `dhl-sdk` |
| USPS | ❌ | ✅ | `usps-api` |

## Webhook Handler Pattern (`app/webhooks/carrier.py`)

```python
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

    # 1. Replay attack prevention
    timestamp_header = request.headers.get("X-Carrier-Timestamp", "")
    try:
        ts = int(timestamp_header)
    except ValueError:
        raise HTTPException(status_code=401, detail="UNAUTHORIZED")
    if abs(time.time() - ts) > 300:
        raise HTTPException(status_code=401, detail="UNAUTHORIZED")

    # 2. HMAC verification — always use compare_digest
    signature_header = request.headers.get("X-Carrier-Signature", "")
    expected = "sha256=" + hmac.new(
        settings.CARRIER_WEBHOOK_SECRET.encode(),
        body,
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(expected, signature_header):
        raise HTTPException(status_code=401, detail="UNAUTHORIZED")

    # 3. Parse and ingest
    payload = await request.json()
    service = ShipmentService(session)
    await service.ingest_carrier_event(payload)
    return {"received": True}
```

## Carrier Status → Internal Status Map

```python
# app/utils/carrier_status_map.py
CARRIER_STATUS_MAP: dict[str, str] = {
    # FedEx
    "PU":  "shipped",           # Picked up
    "IT":  "shipped",           # In transit
    "OD":  "out_for_delivery",  # On delivery vehicle
    "DL":  "delivered",         # Delivered
    # UPS
    "PICKUP":       "shipped",
    "IN_TRANSIT":   "shipped",
    "OUT_FOR_DEL":  "out_for_delivery",
    "DELIVERED":    "delivered",
    # DHL
    "TRANSIT":      "shipped",
    "DELIVERY":     "out_for_delivery",
    "DELIVERED":    "delivered",
}

def map_carrier_status(carrier_status: str) -> str | None:
    """Return internal status or None if no state change needed."""
    return CARRIER_STATUS_MAP.get(carrier_status.upper())
```

## Idempotent Event Ingestion

Carriers may send duplicate webhooks. Guard against duplicate `TrackingEvent` rows:

```python
# app/repositories/tracking_event_repository.py
async def exists(
    self, shipment_id: str, carrier_status: str, occurred_at: datetime
) -> bool:
    result = await self.session.execute(
        select(TrackingEvent).where(
            TrackingEvent.shipment_id == shipment_id,
            TrackingEvent.status == carrier_status,
            TrackingEvent.occurred_at == occurred_at,
        )
    )
    return result.scalar_one_or_none() is not None
```

In the service:
```python
if await self.tracking_repo.exists(shipment_id, payload["status"], occurred_at):
    return  # idempotent — already processed
```

## Polling Fallback Worker (for USPS and webhook failures)

```python
# app/workers/carrier_tasks.py
from celery import shared_task

@shared_task(
    bind=True,
    max_retries=3,
    default_retry_delay=300,  # 5 minutes
)
def poll_carrier_tracking(self, shipment_id: str):
    """
    Fallback: poll the carrier API directly for shipments
    that haven't received a webhook update in > 2 hours.
    """
    ...
```

Schedule with Celery Beat every 2 hours:
```python
# app/workers/__init__.py
from celery.schedules import crontab

celery_app.conf.beat_schedule = {
    "poll-stale-shipments": {
        "task": "app.workers.carrier_tasks.poll_carrier_tracking",
        "schedule": crontab(minute=0),  # every hour
    },
}
```

## Security Rules (non-negotiable)

1. **Always** use `hmac.compare_digest()` — never `==` for signature comparison
2. **Always** reject requests with timestamp older than 5 minutes
3. **Never** log the raw webhook body in production (may contain PII)
4. **Always** return `200` after signature check passes, even if parsing fails — prevents carrier retry storms
5. Store `CARRIER_WEBHOOK_SECRET` in env — never hardcode

## Testing Carrier Webhooks

```python
# tests/integration/test_carrier_webhook.py
import hmac, hashlib, time

def make_signature(body: bytes, secret: str) -> str:
    return "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()

@pytest.mark.asyncio
async def test_valid_webhook_creates_tracking_event(client, seed_shipment):
    body = json.dumps({
        "tracking_number": seed_shipment.tracking_number,
        "carrier": "UPS",
        "status": "OUT_FOR_DEL",
        "location": "Memphis, TN",
        "occurred_at": "2026-05-07T09:00:00Z",
    }).encode()

    resp = await client.post(
        "/webhooks/carrier",
        content=body,
        headers={
            "X-Carrier-Signature": make_signature(body, settings.CARRIER_WEBHOOK_SECRET),
            "X-Carrier-Timestamp": str(int(time.time())),
            "Content-Type": "application/json",
        },
    )
    assert resp.status_code == 200

@pytest.mark.asyncio
async def test_invalid_signature_returns_401(client):
    resp = await client.post(
        "/webhooks/carrier",
        json={"tracking_number": "fake"},
        headers={
            "X-Carrier-Signature": "sha256=invalidsig",
            "X-Carrier-Timestamp": str(int(time.time())),
        },
    )
    assert resp.status_code == 401

@pytest.mark.asyncio
async def test_stale_timestamp_returns_401(client, seed_shipment):
    body = b'{"tracking_number": "test"}'
    resp = await client.post(
        "/webhooks/carrier",
        content=body,
        headers={
            "X-Carrier-Signature": make_signature(body, settings.CARRIER_WEBHOOK_SECRET),
            "X-Carrier-Timestamp": str(int(time.time()) - 400),  # 6+ min ago
        },
    )
    assert resp.status_code == 401
```
