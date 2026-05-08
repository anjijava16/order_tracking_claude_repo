# Frontend Touch / Mobile Design Patterns — Order Tracking

## Mobile-First Principles
- Design for 375px width first, then scale up
- Touch targets minimum **44×44px** (WCAG 2.5.5)
- No hover-only interactions — every feature must work with tap
- Bottom navigation for primary sections (not top hamburger menus)

## Mobile-Specific Patterns

### 1. Bottom Navigation Bar
Primary sections accessible via fixed bottom bar:
```
[📦 Orders] [🔍 Track] [👤 Profile]
```

### 2. Order List — Swipe Actions
- Swipe left on order card → "Cancel Order" (destructive, red) — only for eligible statuses
- Swipe right on order card → "View Details"
- Use `react-swipeable` or similar library
- Show confirmation bottom sheet before cancelling

### 3. Shipment Tracking — Pull to Refresh
- `react-pull-to-refresh` or custom implementation
- Spinner appears below top of list while refreshing
- Invalidate React Query cache on pull-to-refresh

### 4. Bottom Sheets (instead of modals)
Use bottom sheets for:
- Order status change confirmation
- Filter/sort options
- Carrier contact info
Never use full-screen modals on mobile — always animate from bottom.

### 5. Compact Order Status Timeline
On mobile, render timeline **vertically** with left-aligned dots:
```
● Placed         May 5
● Confirmed      May 5
● Processing     May 6
⏳ Shipped       May 7  ← current
○ Delivered
```

### 6. Touch-Friendly Inputs
- Use `type="tel"` for phone number fields
- Use `inputMode="numeric"` for quantity fields
- Use native date picker (`type="date"`) for date filters
- Minimum font size 16px to prevent iOS auto-zoom on focus

## Accessibility on Touch
- All interactive elements have `aria-label` when icon-only
- Status badges include `role="status"` and `aria-live="polite"` for real-time updates
- Focus management: after closing a bottom sheet, return focus to the trigger element
