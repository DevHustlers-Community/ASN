# OpenAPI contracts

One OpenAPI 3.x file per REST service.

| File | Owner |
|---|---|
| `social-api.yaml` | Social API |
| `chat-api.yaml` | Chat service (landed: contract slice 1) |
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

**CI:** [`scripts/contracts/validate.py`](../../scripts/contracts/validate.py)
validates every file with `openapi-spec-validator`, resolves every `$ref`, and
rejects a removed path, operation, or required field without an `info.version`
bump on pull requests. Client generation drift checks are not implemented yet.

**Status:** not written yet for the business services; authoring starts with
the Social API and Chat endpoints needed by the first vertical slice. The
event-broker contract has landed
([`event-broker-api.yaml`](event-broker-api.yaml)) with the broker paths
decided by ADR 0008 (`/v1/...`, which intentionally differs from the `/api/v1`
client convention: the broker is service-to-service only), and
[`chat-api.yaml`](chat-api.yaml) has landed as contract slice 1 (devices,
direct conversations, opaque message envelopes, read cursors) with no
endpoints implemented yet. Chat authentication in `chat-api.yaml` is
provisional pending §9.1: the `chatBearer` scheme name and the 401/403
semantics are stable, the credential format is not. The shared error
envelope question remains open in §9.1; both landed contracts use RFC 9457
Problem Details with a stable `code` extension until that decision.
