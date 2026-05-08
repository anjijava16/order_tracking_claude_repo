# Frontend Design Patterns — Order Tracking UI

## Design Principles
- **Clarity first** — order status must be immediately visible without reading text
- **Progressive disclosure** — show summary on list, details on drill-down
- **Optimistic UI** — update state immediately on user action, revert on error

## Key UI Patterns

### 1. Order Status Timeline
Display a horizontal (desktop) or vertical (mobile) stepper showing all stages.
- Completed steps: filled icon + solid color
- Current step: pulsing indicator
- Future steps: muted/gray

```
[✅ Placed] → [✅ Confirmed] → [⏳ Processing] → [○ Shipped] → [○ Delivered]
```

### 2. Order Card Component
Used in list views. Shows:
- Order ID (`ORD-20260507-00042`)
- Customer name (admin view) or "Your Order" (customer view)
- Status badge (color-coded, see frontend rules)
- Total price
- Last updated timestamp
- CTA: "Track Shipment" button (visible once status ≥ `shipped`)

### 3. Tracking Map / Timeline
On the Order Detail page, show TrackingEvents as a reverse-chronological list:
```
[2026-05-07 14:32]  Out for delivery — Memphis, TN
[2026-05-06 09:10]  Arrived at sort facility — Nashville, TN
[2026-05-05 18:00]  Picked up by carrier
```

### 4. Empty States
- No orders yet: illustration + "Place your first order" CTA
- No tracking events: "Tracking info will appear once your order ships"
- Search/filter returns nothing: "No orders match your filters" + clear filters button

### 5. Loading States
- Use skeleton loaders (not spinners) for list and detail pages
- Skeleton should match the shape of the real content

### 6. Error States
- API error on order list: inline error banner with retry button
- Order not found: full-page 404 with "Back to Orders" link
- Auth error: redirect to `/login` with `?redirect=` parameter

## Color Tokens (Tailwind)
```
status-pending:    bg-gray-100   text-gray-700
status-confirmed:  bg-blue-100   text-blue-700
status-processing: bg-yellow-100 text-yellow-700
status-shipped:    bg-purple-100 text-purple-700
status-otd:        bg-orange-100 text-orange-700
status-delivered:  bg-green-100  text-green-700
status-cancelled:  bg-red-100    text-red-700
```
