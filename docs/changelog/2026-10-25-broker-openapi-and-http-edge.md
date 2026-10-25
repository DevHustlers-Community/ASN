---
date: 2026-10-25
type: feat
scope: services
summary: Land the broker OpenAPI contract and the Plug/Bandit HTTP edge with bearer auth
breaking: false
adr: "0008"
contracts: openapi/event-broker-api.yaml
---

# Land the broker OpenAPI contract and HTTP edge

## Change

- Added `contracts/openapi/event-broker-api.yaml` (OpenAPI 3.1): the full v1
  REST surface of ADR 0008 — publish (201/200/409/422 with the Problem
  Details error envelope and stable `code`), claims with long-poll request
  and canonical envelope responses, ack/nack/extend/skip, dead delivery
  inspection, replay, subscription list/create, and unauthenticated
  health/ready. Paths are `/v1/...` per the ADR, intentionally distinct from
  the `/api/v1` client convention (the broker is service-to-service only).
- Added `AsnEventBroker.Web.Router` (Plug, served by Bandit): authentication
  and request validation at the edge only — bearer-token auth delegating to
  `Security`, scope enforcement per route, the 256 KiB whole-body limit
  enforced before parsing (413), RFC 9457 Problem Details for every error
  with a stable `code`, and claim responses carrying the canonical envelope
  plus delivery metadata. Health endpoints bypass auth.
- Added `AsnEventBroker.Security`: credential issuance (random token returned
  once, stored SHA-256), constant-time verification against non-revoked
  unexpired credentials, per-credential `allowed_event_types` publish
  restrictions, revocation, and first-boot admin bootstrap from
  `BROKER_ADMIN_TOKEN` (only when the credentials table is empty).
- Bandit joins the supervision tree behind `config :asn_event_broker, :http`
  (enabled, port 4004); disabled in tests, where the router runs through
  `Plug.Test`.
- HTTP integration tests: auth matrix (no token, wrong scope, allow-list
  rejection), publish outcome codes over the wire, claim/ack/nack flows,
  duplicate idempotent ack, paused 409, admin-scoped replay with audit
  entries, 413, and 404 problem details.

## Why

Contract-first per the architecture rules: the OpenAPI file landed before the
adapter, and the adapter contains no routing, lease, retry, or retention
rules — it maps requests onto the already-tested domain modules (broker
CODE_MAP transport boundary).

## Verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test` — run; 57/57 pass; `broker_db_test` empty after the suite.
- `python3 -c "import yaml; yaml.safe_load(...)"` — OpenAPI YAML parses.
- `python3 scripts/ci/check-changelog.py --all` — run; pass.

## Follow-ups

- Phase 7 telemetry emission; phase 8 chat outbox relay end-to-end; phase 9
  property-based concurrency tests. Spectral/Redocly lint lands with the
  shared contracts tooling (`scripts/contracts/`, still planned).
