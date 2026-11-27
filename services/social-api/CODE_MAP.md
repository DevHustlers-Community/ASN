# Social API code map

Companion to the [service README](README.md). Social is an API-only Elixir/OTP
application under ADR 0018.

## Boundaries

- Only `AsnSocial.Repo` accesses `social_db`.
- No service reads or writes another service's database.
- Domain rules and transactions live in contexts; controllers remain thin.
- Business changes and outbox events commit atomically.
- Query paths follow ADR 0018: bounded selects, keyset pagination, explicit
  indexes, query-plan evidence, and N+1 prevention.

## Runtime

| Path | Responsibility |
|---|---|
| `lib/asn_social/application.ex` | Supervision tree |
| `lib/asn_social/repo.ex` | `social_db` boundary |
| `lib/asn_social/uuid_v7.ex` | RFC 9562 UUIDv7 placeholder pending the library ADR |
| `lib/asn_social/accounts.ex` | Account creation and authorization lookup |
| `lib/asn_social/accounts/user.ex` | User schema, changeset, and authorization view |
| `lib/asn_social/events/` | Transactional outbox and user event builders |
| `lib/asn_social/auth/` | Auth0 M2M JWT, JWKS, and development key handling |
| `lib/asn_social_web/` | API-only router, controllers, plugs, telemetry, and Problem Details |
| `lib/mix/tasks/asn_social.dev_token.ex` | Development M2M token minting |
| `priv/repo/migrations/` | Social-owned forward-only migrations |
| `test/` | ExUnit, real-PostgreSQL integration, API, auth, and query-plan tests |

## Current HTTP surface

- `GET /healthz`
- `GET /readyz`
- `GET /internal/v1/users/{user_id}/authorization` with an Auth0 M2M token and
  `social:authorization:read` scope.

## Follow-ups

- Account provisioning/Auth0 Action contract.
- Remaining `user.*` lifecycle events and aggregate-version handling.
- Social outbox relay.
- Social to broker to Chat projection E2E.
- Public Social resource APIs and feed/timeline query benchmarks.
