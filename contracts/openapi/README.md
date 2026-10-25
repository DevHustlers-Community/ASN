# OpenAPI contracts

One OpenAPI 3.x file per REST service.

| File | Owner |
|---|---|
| `social-api.yaml` | Social API |
| `chat-api.yaml` | Chat service |
| `moderation-api.yaml` | Moderation API |
| `event-broker-api.yaml` | Event broker (ADR 0008, accepted: HTTP claim-based pull) |

**Conventions:**

- Base path `/api/v1/`; plural resource paths.
- RFC 9457 Problem Details for errors, with a stable `code` and a request ID.
- Cursor pagination for timelines and message history; explicit allow-lists for
  filters and sort keys.
- Idempotency keys documented per create/command operation.
- Chat message endpoints accept and return opaque envelope metadata plus bytes;
  there is no plaintext body field.
- Response types are generated into [`packages/api-client`](../../packages/api-client/README.md).

**CI:** lint (e.g. Redocly/Spectral), breaking-change detection against the base
branch, and client generation drift check.

**Status:** not written yet for the business services; authoring starts with
the Social API and Chat endpoints needed by the first vertical slice. The
event-broker contract has landed
([`event-broker-api.yaml`](event-broker-api.yaml)) with the broker paths
decided by ADR 0008 (`/v1/...`, which intentionally differs from the `/api/v1`
client convention: the broker is service-to-service only). The shared error
envelope question remains open in §9.1; the broker uses RFC 9457 Problem
Details with a stable `code` extension until that decision.
