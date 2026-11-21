# 0016 - REST authentication and request policy

- Status: accepted
- Date: 2026-11-09
- Supersedes: -

## Context

Architecture §9.1 leaves the shared REST authentication and request policy open:
the error envelope, token/session strategy, service-to-service authentication,
rate-limit policy, and OpenAPI ownership. Every Chat endpoint is blocked on this
decision, and Social and Moderation will inherit the same rules.

The fixed constraints are:

- Auth0 is the identity provider. `social_db.users` stores `auth0_sub` and
  `sessions_valid_after`; Chat keeps a read-only `chat_users` projection with the
  same `id` as `social_db.users.id` (architecture §3.1, §4.1).
- Services own their databases and do not read each other's data. Cross-service
  authorization data arrives through events, explicit service APIs, or a
  short-lived cache, never through a direct cross-database read.
- REST is the only HTTP API style. WebSockets are live delivery only.
- Chat messages are opaque envelopes. Authentication must never require the
  server to inspect message content.
- The broker already uses scoped bearer credentials for service-to-service
  access (ADR 0008).
- The Chat contract currently names a provisional `chatBearer` scheme and leaves
  the credential format open.

This ADR records the accepted policy. It does not implement it and does not
change any contract by itself.

## Decision

1. **Access tokens.** Auth0 issues short-lived JWT access tokens. Each API
   validates the signature through the issuer's JWKS and checks `iss`, `aud`,
   `exp`, and `nbf` with a small clock skew. The access-token lifetime is 15
   minutes; refresh and session persistence are client/Auth0 concerns. APIs do
   not keep server-side sessions for REST calls.

2. **User identity claim.** A namespaced custom claim carries
   `social_db.users.id` (UUIDv7). The claim namespace is deployment
   configuration, not a hard-coded hostname. Development defaults to
   `https://asn.example/user_id`; production sets its own namespace through the
   Auth0 Action and each service's configuration. These identifiers are opaque
   strings: they need no registered domain, DNS record, or TLS certificate.
   Changing the namespace later invalidates outstanding tokens only; `user_id`
   values are stable UUIDv7 and stored data does not change. Social sets the
   claim through an Auth0 Action after account creation. Chat and other services
   trust it only after local token validation and never use `auth0_sub` as a
   local authorization key. A missing or malformed claim answers
   `401 unauthorized`.

3. **Audience and scopes.** Each API has its own audience. Development defaults
   are `https://api.asn.example/chat`, `https://api.asn.example/social`, and
   `https://api.asn.example/moderation`; production overrides them through
   configuration. They are opaque identifiers and need no registered domain. A
   token for one audience is rejected by another. Scopes are minimal and
   operation-oriented (`chat:read`, `chat:write`, `chat:devices`); they are
   enforced server-side. Scopes never replace ownership, membership, block, or
   moderation checks.

4. **Device context.** Operations that act on behalf of one installed device
   require an `X-Device-Id` header containing a UUIDv7. In contract slice 1 this
   applies to `POST /conversations/{conversationId}/messages`; future presence,
   typing, and attachment-upload operations follow the same rule. The server
   verifies that the device belongs to the authenticated user and is `active`.
   A missing header answers `400 invalid_request`; an unknown, foreign, or
   revoked device answers `403 forbidden` without revealing which condition
   failed. The request body never carries `sender_device_id`; the server derives
   it from the header and the authenticated user.
   - Why a header rather than a device-bound token: one user may have several
     devices, and re-issuing or refreshing a token per device adds complexity
     without a server-side security gain. The server cannot verify possession of
     a private key in any case; the cryptographic binding remains on the client.
   - Why not a body field: the existing contract intentionally omits
     `sender_device_id` from `SendMessageRequest` so a client cannot claim another
     device.
   - Exception: KeyPackage upload and listing identify the device in the path
     and verify ownership server-side; they do not require `X-Device-Id`
     ([ADR 0017](0017-keypackage-storage-before-library-gate.md)).

5. **Service-to-service authentication.** Services authenticate with Auth0 M2M
   access tokens: short-lived, one audience per target service, and explicit
   scopes. The broker keeps its existing scoped bearer credentials (ADR 0008).
   User tokens are never accepted on service endpoints and service tokens are
   never accepted on user endpoints. mTLS is a later hardening option and does
   not change the application contract.

6. **Shared error envelope.** Every REST API returns RFC 9457
   `application/problem+json` with `type`, `title`, `status`, a stable `code`,
   and `request_id`. Validation failures may add `errors[]`. Responses never
   contain stack traces, SQL, tokens, private keys, or plaintext. The stable
   status mapping is: `401` for missing or invalid authentication, `403` for an
   authenticated caller that is not allowed, `404` for unknown or
   non-member resources where existence must not leak, `409` for idempotency
   conflicts, `422` for semantically unprocessable requests, `429` with
   `Retry-After`, and `503` when a required dependency is unavailable.

7. **Rate limits.** Rate limiting runs at two layers: the edge enforces a coarse
   per-IP limit, and each service enforces per-user, per-device, and
   per-operation limits. Limits are configuration, not code; changing a number
   does not require a contract change. Authentication failures are limited more
   aggressively than successful reads. A limited response is `429` with
   `code: rate_limited` and `Retry-After`.

8. **Revocation and account status.** Every authenticated request performs an
   authoritative authorization check against Social before the handler runs.
   The service calls a narrow internal Social REST endpoint with its M2M token;
   the endpoint returns the account status and `sessions_valid_after`. The
   request is rejected when the account is not active or when the access token
   was issued at or before `sessions_valid_after`. The check is a service API
   call, not a read of `social_db`.
   - The check applies to reads as well as writes. A banned, suspended,
     deletion-pending, or purged account cannot keep reading Chat data with an
     unexpired token.
   - The client uses a short timeout (300 ms by default) and fails closed. On a
     timeout, transport error, non-2xx response, or malformed response, the
     request answers `503` with `code: authorization_unavailable`. It never
     falls back to a stale allow. A fail-closed circuit breaker may
     short-circuit repeated failures, but it cannot return an allow.
   - No stale-allow authorization cache is used for enforcement. Per-request
     memoization is allowed so one request performs at most one check.
   - Social is the source of account status, not a general authorization
     service. Each service still enforces ownership, membership, block, and
     domain rules locally against its own data.
   - The 15-minute token lifetime remains defense in depth. It is no longer the
     revocation bound; the authoritative check is.
   - WebSocket connections use the same check at connect and at the
     revalidation boundaries defined by the live-delivery design. Live delivery
     never outlives an authorization decision.

9. **Transport and request limits.** HTTPS is required outside local
   development. The edge terminates TLS, sets HSTS, and applies a CORS
   allow-list per environment; wildcard origins with credentials are not
   allowed. Request bodies are limited to 256 KiB before parsing, matching the
   Chat and broker contracts. `request_id` is generated or propagated at the
   edge and appears in logs and Problem Details.

10. **OpenAPI ownership.** Each service owns its file under
    `contracts/openapi/`. Changes are additive within `info.version`; removing a
    path, operation, or required field requires a version bump, which
    `scripts/contracts/validate.py` enforces on pull requests. Shared Problem
    Details schemas move to `contracts/openapi/common/` when the second service
    adopts them; until then each contract keeps its own copy to avoid premature
    coupling. Clients are generated from these contracts and are never
    hand-edited.

11. **Development and tests.** Local development uses a fixed development
    issuer and a local authorization adapter backed by seeded account state.
    The adapter implements the same interface and the same claim shape as the
    production Social client; it is selected by configuration in dev and test
    only. There is no authentication-skip or authorization-skip flag in any
    environment. Tests sign tokens with fixed test keys, exercise expired
    tokens, missing claims, wrong audiences, status changes, and
    authorization-endpoint failures, and never use real secrets or real user
    data.

## Consequences

- Chat can implement the authentication plug and the first controllers now that
  this ADR is accepted.
- `chat-api.yaml` gains an `X-Device-Id` header on send-message and the
  `chatBearer` description is finalized. These are additive contract changes.
- Social must add the `user_id` claim through an Auth0 Action, expose the
  internal authorization endpoint, and emit the `user.*` and `user.blocked` /
  `user.unblocked` events. Until then, Chat uses the development authorization
  adapter and fixtures.
- Every authenticated request adds one internal Social round trip. Chat
  availability for authenticated operations is bounded by Social availability;
  this is the accepted cost of immediate revocation. The 300 ms timeout and the
  fail-closed circuit breaker limit blast radius and retry storms.
- Rate-limit numbers are environment configuration; only the response shape is
  contractual.
- Service tokens introduce a dependency on the M2M issuer. The authoritative
  check introduces a synchronous Chat-to-Social call for every authenticated
  request; it does not introduce a direct cross-database dependency or a
  Social-to-Chat call.
- Development and tests use a local authorization adapter with the same
  interface; production has no bypass.
- 401/403 semantics become stable across services.

## Alternatives considered

- **Event-fed authorization cache with bounded staleness and fail-closed.**
  Rejected as the primary enforcement: event lag or cache age would delay
  revocation, and the design would have to prove a freshness bound. It may
  return later only as an optimization that cannot weaken the authoritative
  check.
- **Server-side sessions in Social with per-request introspection.** Rejected as
  a general session model: it would make Social the session authority for every
  service. This ADR adopts only a narrow authorization-status check; token
  authenticity is still validated locally.
- **Opaque tokens with introspection.** Rejected: it validates token
  authenticity remotely as well as authorization freshness. This ADR keeps
  signature validation local through JWKS and makes only the authorization
  check remote.
- **Long-lived JWTs.** Rejected: revocation after bans or device loss would be
  too slow.
- **Device-bound tokens.** Deferred: stronger on paper, but Auth0 issuance and
  refresh per device add complexity without a server-side proof of private-key
  possession.
- **mTLS for service-to-service calls.** Deferred: operationally heavier than
  signed M2M tokens and not required for the first deployment.
- **A shared error-envelope package now.** Deferred until the second REST service
  lands; the contracts already fix the shape.

## Follow-ups

- Add `X-Device-Id` to `contracts/openapi/chat-api.yaml` and finalize the
  `chatBearer` description.
- Implement the Chat authentication plug, the authoritative authorization client
  with its development adapter, and the first device controllers.
- Define Social's internal authorization endpoint and its M2M contract before
  Chat runs in production.
- Define and emit the Social `user.*` and `user.blocked` / `user.unblocked`
  event contracts, then add the Chat projection consumers.
- Set per-environment rate-limit values and the edge CORS allow-list.
- Move shared Problem Details schemas to `contracts/openapi/common/` when Social
  starts.
