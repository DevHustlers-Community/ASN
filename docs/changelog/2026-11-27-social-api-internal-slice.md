---
date: 2026-11-27
type: feat
scope: social
summary: Adopt the Social Elixir runtime and implement internal authorization
breaking: false
adr: 0016, 0018
contracts: contracts/openapi/social-api.yaml, contracts/events/social/user.created.v1.schema.json
---

# Implement Social API internal authorization slice

## Change

- Added accepted ADR 0018 selecting Elixir, Phoenix API-only, Ecto, and
  PostgreSQL for Social, with keyset pagination, bounded queries, index/query-plan
  evidence, N+1 prevention, and measured feed optimization as service contracts.
- Updated the architecture stack, AGENTS baseline, roadmap, service maps, and
  development documentation. Bun now applies to Moderation and the web toolchain.
- Scaffolded `services/social-api` as a Phoenix API-only/Ecto OTP application on
  the ADR 0018 baseline, with its own lockfile and configuration.
- Added `users`, `outbox_events`, and `processed_events` migrations with account
  status checks, citext username uniqueness, authorization indexes, and typed
  outbox constraints.
- Added Auth0 M2M JWT verification, HTTPS JWKS resolution with bounded cache,
  scope enforcement, development key handling, and a development token Mix task.
- Added `GET /internal/v1/users/{user_id}/authorization`, health/readiness,
  RFC 9457 errors, request IDs, and the 256 KiB request limit.
- Added transactional account creation with a `user.created` outbox event and
  its versioned JSON Schema/example.
- Added Social OpenAPI documentation and included it in the Swagger viewer.
- Added Social CI and Hex audit coverage, plus `social_db_test` initialization.
- Added ExUnit coverage for M2M tokens, account/outbox atomicity, authorization
  API behavior, UUIDv7, and the authorization primary-key query plan.

## Why

Chat's production authorization path depends on a Social internal endpoint that
did not exist. This slice establishes the accepted Elixir runtime and the first
real Social-owned database/event path without changing REST or broker contracts.

## Verification

- Social `mix format --check-formatted` and `mix compile --warnings-as-errors` — clean.
- Social `mix test` — 20 passed.
- Social `mix hex.audit` — no retired or security advisory packages.
- Development seed and `mix asn_social.dev_token` verification — passed.
- `scripts/contracts/validate.py --base-ref upstream/main` — OpenAPI and event
  contracts OK.
- Workflow YAML parsing, shell syntax, documentation links, and
  `git diff --check` — clean.

## Follow-ups

- Auth0 Action/account-provisioning contract.
- Remaining `user.*` lifecycle events and aggregate-version handling.
- Social outbox relay and Social → broker → Chat projection E2E.
- Service-level rate limiting for internal endpoints.
