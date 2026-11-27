# Social API

Elixir + Phoenix API-only + Ecto service that owns `social_db`.

**Status:** the first internal slice is implemented under
[ADR 0018](../../docs/decisions/0018-social-api-elixir-phoenix-ecto.md): users and
account status, the M2M-protected authorization endpoint required by Chat,
transactional outbox storage, and the `user.created` event. Public Social
resource APIs, account provisioning, remaining `user.*` events, and the outbox
relay are follow-ups.

## Owns

- Accounts and Auth0 identity mapping.
- Profiles and privacy settings.
- Follows and platform-wide blocks.
- Posts, media metadata, comments, likes, reposts, and hashtags.
- Feed inputs, candidate selection, and ranking.
- Articles and revisions.
- Communities, roles, channels, invites, and community reports.
- Notifications, plans, subscriptions, feature flags, and account deletion.
- Activity calendar and login streaks.

## Does not own

- Friendships, conversations, messages, or chat devices.
- Moderation reports, cases, appeals, or staff audit logs.
- The event log or any other service's database.

## Runtime and layout

- Elixir 1.20.4 / OTP 29.1.2.
- Phoenix 1.8.17 in API-only mode: no HTML, LiveView, or asset pipeline.
- Ecto 3.14 / Postgrex 0.22.
- PostgreSQL 18.6 locally.
- Bandit 1.15.
- OTP application `:asn_social`; root module `AsnSocial`; web module
  `AsnSocialWeb`.

Layout:

```text
services/social-api/
├── config/
├── lib/
│   ├── asn_social/
│   │   ├── application.ex
│   │   ├── repo.ex
│   │   └── <context>/
│   └── asn_social_web/
├── priv/repo/migrations/
├── test/
└── mix.exs
```

Domain contexts own business rules, authorization, transactions, and queries.
Controllers map HTTP to context calls and remain thin.

## Boundaries

- REST only, documented in `contracts/openapi/social-api.yaml`.
- Emits `user.*`, `community.*`, `channel.*`, `member.*`, and
  `subscription.*` events; consumes `friendship.*` for `friend_edges`.
- Never reads or writes `chat_db`, `moderation_db`, or `broker_db`.
- Business changes and outbox events commit in the same `social_db` transaction.
- Private community content never reaches public feeds, search, trends,
  notifications, or global reposts; enforce one visibility policy at every read
  and materialization boundary.

## Performance and query rules

ADR 0018 makes query optimization a service contract:

- Keyset/cursor pagination with bounded page sizes for feeds, timelines, search,
  and other large or volatile collections.
- Select only required columns and return minimal DTOs; avoid loading large text,
  JSON, or binary fields for list endpoints.
- Add indexes with the migration that introduces each critical access path and
  verify them with query plans on representative data volumes.
- Prevent N+1 queries with explicit joins or batched preloads; measure row
  multiplication before choosing a strategy.
- Separate feed candidate selection from ranking; begin with bounded SQL
  candidate queries and benchmark before adding infrastructure.
- Keep counters asynchronously maintained and rebuildable.
- Configure bounded pools, query/request timeouts, and telemetry for query
  duration, pool queue time, errors, and endpoint latency.
- Record throughput, p95/p99 latency, CPU, memory, and query-plan evidence before
  changing partitioning or scaling strategy.

## Implemented internal slice

1. Phoenix API-only/Ecto application with CI.
2. `social_db` users/account-status migration, constraints, and indexes.
3. Social OpenAPI contract for health/readiness and M2M-protected authorization.
4. Auth0 JWT/M2M verification with JWKS rotation and scope enforcement.
5. Transactional outbox storage and the `user.created` payload contract.
6. Real-PostgreSQL tests for account creation, atomic outbox writes, API
   authorization, and the authorization primary-key query plan.

## Local development

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

The API listens on `http://localhost:4001`. Development uses a gitignored local
RSA key. Mint an M2M token for Chat with:

```bash
mix asn_social.dev_token --client-id chat-service
```

Production requires `SOCIAL_DATABASE_URL`, `SECRET_KEY_BASE`, and the
`ASN_SOCIAL_AUTH_*` issuer/audience/JWKS configuration. Missing JWKS fails closed.

## Follow-ups

- Auth0 Action/account-provisioning contract.
- Remaining `user.*` lifecycle events and aggregate-version handling.
- Social outbox relay to the custom broker.
- Social → broker → Chat projection E2E.

## Tests

Run from the service directory:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Database tests use a real PostgreSQL instance and Ecto Sandbox. Critical query
paths also require index/query-plan tests and feed/timeline load tests.
