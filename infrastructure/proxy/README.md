# Edge proxy

Nginx (or equivalent) configuration for TLS termination and routing.

**Routing:**

| Path | Upstream |
|---|---|
| `/api/v1/social/*`, `/api/v1/users/*`, `/api/v1/posts/*`, `/api/v1/feed/*`, `/api/v1/communities/*` | Social API |
| `/api/v1/conversations/*`, `/api/v1/devices/*`, `/socket/*` | Chat service |
| `/api/v1/reports/*`, `/api/v1/moderation/*`, `/api/v1/appeals/*` | Moderation API |
| `/api/v1/events/*`, `/api/v1/subscriptions/*`, `/api/v1/deliveries/*` | Event broker (internal only) |

**Rules:**

- The proxy terminates TLS and enforces request-size limits and basic rate
  limits. It does not authorize resources or own business logic.
- The broker API is not exposed to public clients.
- Forward a request/correlation ID and the original client IP through trusted
  headers only.
- No response caching for authenticated or chat endpoints.
- WebSocket upgrade is allowed only on the Chat channel path.

**Status:** not written yet; the route table lands with the first deployable
service.
