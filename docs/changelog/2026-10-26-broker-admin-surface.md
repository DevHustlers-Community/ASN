---
date: 2026-10-26
type: feat
scope: services
summary: Add subscription update and credential management to the broker admin surface
breaking: false
adr: "0008"
contracts: openapi/event-broker-api.yaml
---

# Add subscription update and credential management endpoints

## Change

- Extended `contracts/openapi/event-broker-api.yaml` (contract-first):
  `PATCH /v1/subscriptions/{name}` (pause/resume, `event_types` re-filtering,
  retry budget, admin-scoped) and the credential surface
  (`GET /v1/credentials`, `POST /v1/credentials` with a one-time plaintext
  token response, `POST /v1/credentials/{id}/revoke`), plus
  `CredentialInput`/`CredentialIssued`/`CredentialView` schemas that never
  expose tokens or hashes.
- Implemented both in the edge router with the same Problem Details errors
  and scope enforcement. Unknown scope names are rejected with 400 before
  any atom conversion.
- `Security.issue/3` and `Security.revoke/2` now write audit entries
  (`credential.create`, `credential.revoke`) per ADR 0008 §9 — the plaintext
  token is never recorded, and the bootstrap credential is its own audit
  actor. Subscription updates are audited (`subscription.update`).
- HTTP tests: pause/resume with claims flipping 409/200, filter updates
  applying to new fan-out, issue/list-without-secrets/revoke-blocking-access,
  audit entries for all three admin actions, and unknown-scope rejection.

## Why

The ADR §2 REST surface promised subscription updates and credential
rotation; both are now operable over HTTP, closing the last admin gap before
real consumers onboard (pause/resume is the primary maintenance tool when a
consumer is down).

## Verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test` — run; 67 pass (3 properties, 64 tests); `broker_db_test` empty
  after the suite.
- OpenAPI YAML parses (`python3 -c "import yaml; ..."`) — Spectral/Redocly
  lint still lands with `scripts/contracts/`.

## Follow-ups

- Metrics exposition (`/metrics`) remains the last broker v1 surface item;
  the cross-service e2e harness follows with the next service.
