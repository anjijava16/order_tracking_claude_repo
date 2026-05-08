# Frontend Rules

## Tech Stack
- **React 18** + **TypeScript** (strict mode)
- **Zustand** for global state
- **React Query (TanStack Query)** for server state + caching
- **React Router v6** for routing
- **Axios** (typed via `frontend/src/api/`) for HTTP calls
- **Vitest** + **React Testing Library** for tests

## Component Rules
- Functional components only — no class components
- One component per file; filename matches component name (`OrderCard.tsx`)
- Props interfaces named `<ComponentName>Props` and defined above the component
- No inline styles — use Tailwind CSS utility classes

## File Structure (`frontend/src/`)
```
components/     # Reusable UI components (Button, Badge, OrderCard)
pages/          # Route-level page components (OrderListPage, OrderDetailPage)
hooks/          # Custom React hooks (useOrder, useTrackingEvents)
store/          # Zustand slices (authStore, orderStore)
api/            # Typed Axios client + query/mutation hooks
types/          # Shared TypeScript interfaces (mirrors backend Pydantic schemas)
utils/          # Pure helper functions
```

## API Client Rules
- All API calls go through `frontend/src/api/client.ts` (Axios instance with base URL + auth header interceptor)
- Each domain has its own module: `frontend/src/api/orders.ts`, `frontend/src/api/shipments.ts`
- Use React Query `useQuery` / `useMutation` wrappers — no raw `axios` calls in components

## State Management
- **Server state** (orders, shipments, products) — React Query only
- **UI state** (modal open, selected filters) — local `useState`
- **Auth state** (current user, tokens) — Zustand `authStore`

## Order Status Display
Map backend enum values to user-friendly labels and badge colors:
| Status | Label | Color |
|---|---|---|
| `pending` | Pending | Gray |
| `confirmed` | Confirmed | Blue |
| `processing` | Processing | Yellow |
| `shipped` | Shipped | Purple |
| `out_for_delivery` | Out for Delivery | Orange |
| `delivered` | Delivered | Green |
| `cancelled` | Cancelled | Red |

## Error Handling
- Show user-friendly messages for `4xx` errors (map `error.code` from API envelope)
- Show generic "Something went wrong" for `5xx` errors
- Never expose raw error messages or stack traces to users

## Testing
- Test each component with at least: render test, user interaction test, loading/error state test
- Mock API calls using `msw` (Mock Service Worker)
- Test files colocated: `OrderCard.test.tsx` next to `OrderCard.tsx`
