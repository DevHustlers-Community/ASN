---
date: 2026-11-22
type: feat
scope: chat
summary: Implement REST authentication, request policy, and device HTTP endpoints per ADR 0016
breaking: false
adr: 0016
contracts: contracts/openapi/chat-api.yaml
---

# Implement REST authentication, request policy, and device HTTP endpoints

## Change

- Added `docs/decisions/0016-rest-authentication-and-request-policy.md` with
  status `accepted`. It covers Auth0 JWT access tokens, the namespaced
  `user_id` claim, per-service audiences and scopes, `X-Device-Id` for
  device-scoped operations, Auth0 M2M service tokens, RFC 9457 Problem Details,
  two-layer rate limits, transport and request limits, and OpenAPI ownership.
- The claim namespace and audience identifiers are deployment configuration.
  Development defaults use `asn.example` only as an opaque placeholder; they
  require no registered domain, DNS record, or TLS certificate. A later change
  invalidates outstanding tokens only and does not migrate stored data.
- Every authenticated request performs an authoritative authorization check
  against a narrow internal Social endpoint before the handler runs. The check
  applies to reads and writes, has a 300 ms timeout, and fails closed with
  `503 authorization_unavailable`. There is no stale-allow cache. Development
  uses a local adapter with the same interface; production has no bypass.
- Added ADR 0016 to the recorded table in `docs/decisions/README.md` and updated
  the status summary.
- Updated architecture §9 item 1 to mark the policy settled and point to
  ADR 0016. Updated §9 item 5 to note that account status and session revocation
  are settled while block and community-removal propagation remain open.

### Chat service

- Added `jose` and the `AsnChat.Auth` stack: JWT verification with a
  configurable algorithm allow-list, issuer/audience/expiry/not-before checks,
  JWKS resolution with a bounded cache, and the namespaced UUIDv7 `user_id`
  claim.
- The 503 responses are split by cause as ADR 0016 §8 requires: an unavailable
  signing-key source answers `code: service_unavailable`, while a failed
  authoritative account-status check answers `code: authorization_unavailable`.
  The contract's `ErrorCode` lists both.
- `ASN_AUTHORIZATION_ADAPTER=dev` is now dev/test only: production always runs
  `SocialClient` and fails at boot if `dev` is requested. Missing
  `SOCIAL_INTERNAL_URL` or `ASN_M2M_TOKEN` still fails closed with 503 rather
  than raising at boot, because the Social endpoint is a documented follow-up
  and fail-closed is the accepted behavior.
- Added `AsnChat.Authorization` with two adapters. `DevAdapter` reads the
  `chat_users` projection; `SocialClient` calls the future Social internal
  endpoint with an M2M token and fails closed until that endpoint and token are
  configured.
- Added `AsnChatWeb.Plugs.Authenticate`, `AsnChatWeb.Problem` (RFC 9457),
  `AsnChatWeb.Plugs.BodyLimit` (256 KiB), and Problem-shaped fallback errors.
  A `ProblemContentType` plug rewrites Phoenix's negotiated JSON error responses
  to `application/problem+json`. Required scopes are checked before the remote
  authorization call so a missing scope cannot produce a Social round trip.
- JWKS and Social fetches require HTTPS with peer and hostname certificate
  verification; an empty environment value is treated as unset; a stale JWKS
  cache is bounded by `jwks_max_stale_ms`.
- Implemented the device operations: `GET /api/v1/devices` (`chat:read`),
  `POST /api/v1/devices` and `POST /api/v1/devices/:device_id/revoke`
  (`chat:devices`). Ownership and lifecycle rules stay in `AsnChat.Devices`.
- Added `mix asn_chat.dev_token` to mint development tokens from a generated,
  gitignored key under `priv/dev/`, plus a development-only seed for the local
  `chat_users` row. Runtime configuration reads `ASN_AUTH_ISSUER`,
  `ASN_AUTH_AUDIENCE`, `ASN_AUTH_USER_ID_CLAIM`, `ASN_AUTH_JWKS_URL`,
  `ASN_AUTHORIZATION_ADAPTER`, `SOCIAL_INTERNAL_URL`, and `ASN_M2M_TOKEN`.
- Added token unit tests (including expired, wrong-key, unknown-kid, and
  disallowed-algorithm cases) and device API integration tests covering missing
  and malformed credentials, inactive accounts, unavailable authorization,
  scope enforcement, idempotent registration and revocation, cross-user
  isolation, validation failures, and the body limit. A dedicated test pins
  `Token.verify/2` with no key source to `:jwks_unavailable` and the plug's
  error mapping to `service_unavailable` versus `authorization_unavailable`.
  Unit tests with an injected HTTP getter cover the production `SocialClient`
  paths: active,
  inactive, stale token, equal-cutoff, malformed body, missing cutoff, and
  dependency failure. `Jwks` tests cover stale-cache reuse and rejection of
  non-HTTPS URLs.

### Contract

- `contracts/openapi/chat-api.yaml`: `chatBearer` is now a final Auth0 JWT
  scheme instead of provisional; added the required `X-Device-Id` header
  parameter for `sendMessage`; added `internal_error` to `ErrorCode`; documented
  `403` on the device operations. All changes are additive and the contract
  version is unchanged.

## Why

Architecture §9.1 kept the REST authentication and request policy open, and
every Chat endpoint depends on it: handlers need a trusted `user_id`,
`sendMessage` needs a verified sending device, and the error, rate-limit, and
request-limit shapes must be fixed before the first controller. Without an
accepted decision, the first implementation would either be unauthenticated or
invent policy outside the documented decisions.

The authoritative per-request check was chosen over an event-fed cache because
it makes revocation immediate: event lag or cache age cannot silently weaken
enforcement. The accepted cost is that Chat availability for authenticated
operations depends on Social availability; the timeout and fail-closed circuit
breaker bound the blast radius.

## Verification

- `mix format --check-formatted` — clean
- `mix compile --warnings-as-errors` — clean
- `mix test` — the full Chat suite (151 tests) passes against local PostgreSQL 18.6
- Development seed and token path — `mix run priv/repo/seeds.exs` inserts the
  dev user; `mix asn_chat.dev_token` verifies and `DevAdapter.authorize/2`
  returns `:ok` against that row
- `python3 scripts/contracts/validate.py --base-ref origin/main` — contracts
  validation OK (run in a local virtualenv because the system Python lacks
  `jsonschema`)
- `git diff --check` — clean
- `python3 scripts/ci/check-links.py` — relative documentation links OK
- `python3 scripts/ci/check-changelog.py --all` — change records OK

## Follow-ups

- Define Social's internal authorization endpoint and its M2M contract before
  Chat runs in production; production `SocialClient` stays fail-closed until
  `SOCIAL_INTERNAL_URL` and an M2M token provider are configured. The current
  `ASN_M2M_TOKEN` is a static string with no refresh, so a long-lived process
  will fail closed after the token expires; wire a short-lived token provider
  (the adapter already accepts a 0-arity function).
- Define the Social `user.*` and `user.blocked` / `user.unblocked` event
  contracts before the Chat conversation endpoints depend on their projections.
- Add per-request rate limiting; ADR 0016 fixes the response shape but the
  values and middleware are not implemented.
- Narrow the broad `rescue _` in `AsnChat.Authorization.authorize/2` and
  `AsnChat.Authorization.SocialClient.authorize/3` so real programming errors
  are not reported as `authorization_unavailable`.
- Configure the `:httpc` session count or replace the client with a pooled one
  before production: the authorization check runs on every request with a
  300 ms timeout, and `:httpc`'s default of two sessions can queue under load.
- Then add conversations, messages, and read cursors.
- Set per-environment rate-limit values and the edge CORS allow-list.
