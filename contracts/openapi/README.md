# OpenAPI contracts

One OpenAPI 3.x file per REST service.

| File | Owner |
|---|---|
| `social-api.yaml` | Social API |
| `chat-api.yaml` | Chat service |
| `moderation-api.yaml` | Moderation API |
| `event-broker-api.yaml` | Event broker, only if ADR 0008 selects an HTTP transport |

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

**Status:** not written yet. Authoring starts with the Social API and Chat
endpoints needed by the first vertical slice. The broker OpenAPI file waits on
ADR 0008.
