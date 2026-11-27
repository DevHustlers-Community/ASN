# OpenAPI contracts

One OpenAPI 3.x file per REST service.

| File | Owner |
|---|---|
| `social-api.yaml` | Social API |
| `chat-api.yaml` | Chat service (contract slice 1; authentication and device operations implemented) |
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
validates every file with `openapi-spec-validator`, resolves every `$ref`, rejects
a repeated YAML mapping key, and rejects a removed path, operation, or required
field without an `info.version` bump on pull requests. Client generation drift
checks are not implemented yet.

**Status:** the Social API contract has landed for its first internal slice
([`social-api.yaml`](social-api.yaml)): health/readiness and the M2M-protected
account authorization endpoint. The Moderation API contract is not written yet.
The event-broker contract has landed
([`event-broker-api.yaml`](event-broker-api.yaml)) with the broker paths
decided by ADR 0008 (`/v1/...`, which intentionally differs from the `/api/v1`
client convention: the broker is service-to-service only), and
[`chat-api.yaml`](chat-api.yaml) has landed as contract slice 1 (devices,
direct conversations, opaque message envelopes, read cursors). Chat
authentication follows
[ADR 0016](../../docs/decisions/0016-rest-authentication-and-request-policy.md):
the `chatBearer` scheme is an Auth0 JWT validated against the issuer JWKS, and
the device and KeyPackage upload operations are implemented. Conversation,
message, and read cursor operations remain contract-only. All landed contracts
use RFC 9457 Problem Details with a stable `code` extension.

## Chat slice 1 coverage

The schema admits states that no operation can reach yet. They are intentional
gaps of the first slice, not implemented behaviour: do not build UI or tests that
assume they are reachable.

| State in the contract/schema | Missing operation |
|---|---|
| `MessageView.deleted_at` with `payload` absent | delete/tombstone message |
| `MessageView.edited_at` | edit message (new `revision_no`) |
| `conversations.kind = community` | create community conversation |
| `conversation_members.role = admin` | change member role |
| `conversation_members.left_at` | add, remove, or leave a member |
| `conversation_members.muted_until` | mute/unmute a conversation |
| `chat_devices.status = pending_verification` | transition device verification state |
| `chat_devices.device_label` | rename a device |
| Delivery and read receipts | receipt endpoints |
| `device_key_packages` claim | upload landed per ADR 0017; atomic claim is deferred until `blocks/` and rate limiting exist |

`processed_events` and `message_payloads` are internal: they are written by the
service inside the send transaction and deliberately have no endpoint of their
own. `chat_users` is a projection, so profile fields come from the Social API.
