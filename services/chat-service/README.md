# Chat service

Elixir + Phoenix + Ecto service that owns `chat_db`.

**Status:** API-only service with authentication and device endpoints
implemented. The service compiles, boots, and connects to PostgreSQL. Contract
slice 1 has landed — the OpenAPI contract
([`contracts/openapi/chat-api.yaml`](../../contracts/openapi/chat-api.yaml)),
the Chat event payload schemas
([`contracts/events/chat/`](../../contracts/events/chat/)), and the
protocol-neutral migrations below. Implemented: the `events` outbox/relay, the
`accounts` projection lock, the `devices` context, REST authentication per
[ADR 0016](../../docs/decisions/0016-rest-authentication-and-request-policy.md),
and the device and KeyPackage operations (`GET /api/v1/devices`,
`POST /api/v1/devices`, `POST /api/v1/devices/:device_id/revoke`,
`POST /api/v1/devices/:device_id/key-packages`, and
`GET /api/v1/devices/:device_id/key-packages`).
Conversations, messages, and read cursors remain contract-only; their contexts
are the next Chat slices. MLS is selected by
[ADR 0007](../../docs/decisions/0007-e2ee-protocol-selection.md); opaque
KeyPackage upload is implemented per
[ADR 0017](../../docs/decisions/0017-keypackage-storage-before-library-gate.md).
Atomic claim is deferred until `blocks/` and rate limiting land, and the client
library gate in ADR 0007 remains open.

Every Chat request body limit is 256 KiB (aligned with the broker's ADR 0008
limit). Bearer tokens are Auth0 JWTs validated against the issuer JWKS with the
namespaced `user_id` claim; every authenticated request performs the
authoritative account-status and session-revocation check against Social and
fails closed with `503 authorization_unavailable` when Social is unreachable.

**Owns:** friendships, chat privacy settings, direct and community
conversations, conversation membership, opaque message envelopes, public device
identity and MLS KeyPackage material, media upload tracking, receipts, push
devices, and chat streaks.

**Does not own:** accounts/profiles (projected from Social), platform blocks
(projected from Social), moderation cases, or the event log.

## Stack

| Component | Baseline |
|---|---|
| Elixir / OTP | 1.20.4 / 29.1.2, pinned in [`.tool-versions`](../../.tool-versions) |
| Phoenix | 1.8.16, API-only (`--no-html`, `--no-assets`, `--no-live`) |
| HTTP adapter | Bandit 1.13.1 |
| Persistence | Ecto 3.14 / Ecto SQL 3.14 / Postgrex 0.22 |
| Database | PostgreSQL 18.6 locally via [`compose.yaml`](../../compose.yaml) |

The OTP application is `:asn_chat`; modules are `AsnChat` and `AsnChatWeb`.

## Code map

See [`CODE_MAP.md`](CODE_MAP.md) for every internal directory, its ownership, and
the status of each context.

| Path | Responsibility |
|---|---|
| `lib/asn_chat/application.ex` | Supervision tree: telemetry, repo, PubSub, endpoint |
| `lib/asn_chat/repo.ex` | The only Ecto boundary for `chat_db` |
| `lib/asn_chat/accounts.ex` | `chat_users` projection access and per-user locking |
| `lib/asn_chat/devices.ex` | Device registration, revocation, listing, and device events |
| `lib/asn_chat/events/` | Outbox writer, wire envelope rebuild, publisher relay |
| `lib/asn_chat/auth/` | JWT verification (`token.ex`, `jwks.ex`) and the development key (`dev_keys.ex`) |
| `lib/asn_chat/authorization/` | Authoritative account-status check: `dev_adapter.ex` and the fail-closed `social_client.ex` |
| `lib/asn_chat/uuid_v7.ex` | UUIDv7 generation |
| `lib/asn_chat_web.ex` | JSON controller and channel helpers |
| `lib/asn_chat_web/endpoint.ex` | Bandit endpoint, body limit, and request pipeline |
| `lib/asn_chat_web/router.ex` | `/api/v1` scopes: authenticated reads and device operations |
| `lib/asn_chat_web/plugs/authenticate.ex` | Bearer authentication, scopes, and per-request authorization check |
| `lib/asn_chat_web/problem.ex` | RFC 9457 Problem Details rendering |
| `lib/asn_chat_web/telemetry.ex` | Endpoint telemetry |
| `config/` | Compile-time configuration plus dev/test/prod/runtime split |
| `priv/repo/migrations/` | Chat-owned migrations: the `chat_db` schema tables from the architecture document (users, conversations, members, devices, messages, message payloads, processed events) plus the outbox table aligned to [ADR 0015](../../docs/decisions/0015-outbox-event-storage.md) |
| `test/` | ExUnit tests and ConnCase/DataCase support |

## Contexts (`lib/asn_chat/`)

| Context | Status | Purpose |
|---|---|---|
| `accounts/` | Implemented | `chat_users` projection and `FOR NO KEY UPDATE` user lock |
| `conversations/` | Planned | Direct/community conversations, membership, privacy |
| `messages/` | Planned | Sequence issuance, envelopes, edits, tombstones |
| `attachments/` | Planned | Encrypted upload lifecycle |
| `read_receipts/` | Planned | Read cursors and receipts |
| `devices/` | Implemented | Device registry and opaque KeyPackage upload/listing (`device_key_packages`, ADR 0017); atomic claim deferred |
| `crypto/` | Planned | Protocol state, key rotation triggers, envelope validation helpers |
| `blocks/` | Planned | `chat_block_edges` projection and fail-closed checks |
| `delivery/` | Planned | Channel fan-out, push, presence |
| `events/` | Implemented | Outbox writer, publishers, consumers |

Context directories are created when their first implementation lands. Do not add
empty placeholder directories.

## Local development

From the repository root:

```bash
cp .env.example .env
docker compose up -d postgres
cd services/chat-service
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

The API listens on `http://localhost:4002`. Device routes require a bearer token;
in development, mint one with the generated local key:

```bash
mix asn_chat.dev_token --user <chat_users.id> [--ttl 900]
```

The development adapter resolves the token's user against the `chat_users`
projection. `mix ecto.setup` seeds one development user in the `dev`
environment (`0190f1e2-6d7e-7f80-b192-3d4e5f607182`); the seed is skipped in
other environments. The generated key file lives under `priv/dev/` and is
gitignored.

| Operation | Scope | Contract |
|---|---|---|
| `GET /api/v1/devices` | `chat:read` | `listDevices` |
| `POST /api/v1/devices` | `chat:devices` | `registerDevice` |
| `POST /api/v1/devices/:device_id/revoke` | `chat:devices` | `revokeDevice` |
| `POST /api/v1/devices/:device_id/key-packages` | `chat:devices` | `uploadKeyPackage` |
| `GET /api/v1/devices/:device_id/key-packages` | `chat:read` | `listKeyPackages` |

Run the verification loop with:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

`mix test` requires the local PostgreSQL instance because the test alias creates
and migrates `chat_db_test` before running ExUnit.

## Configuration

| Variable | Used by | Notes |
|---|---|---|
| `CHAT_DATABASE_URL` | dev, prod | Full Ecto URL; dev default points at `chat_db` |
| `CHAT_TEST_DATABASE_URL` | test | Dev default points at `chat_db_test` |
| `CHAT_SERVICE_PORT` | all | HTTP port, default `4002` |
| `SECRET_KEY_BASE` | prod | Required in prod; dev/test use explicit non-production placeholders |
| `PHX_HOST` | prod | Public host for URL generation |
| `ASN_AUTH_ISSUER` | all | Expected token `iss`; dev default is the `asn.example` placeholder |
| `ASN_AUTH_AUDIENCE` | all | Expected token `aud` for this service |
| `ASN_AUTH_USER_ID_CLAIM` | all | Namespaced claim carrying `social_db.users.id` |
| `ASN_AUTH_JWKS_URL` | prod | Issuer JWKS endpoint; a missing value fails closed |
| `ASN_AUTHORIZATION_ADAPTER` | dev, test | `dev` selects the local adapter; production always runs `SocialClient` and fails at boot if `dev` is requested |
| `SOCIAL_INTERNAL_URL` | prod | Base URL for Social's internal authorization endpoint |
| `ASN_M2M_TOKEN` | prod | Short-lived Auth0 M2M token for the Social authorization call |

The local roles and database names are created by
[`infrastructure/postgres/init/`](../../infrastructure/postgres/init/). Never
connect the Chat role to `social_db`, `moderation_db`, or `broker_db`.

## Hard rules

- No plaintext message body exists in any column, DTO, log, event, trace, or push
  payload. Envelope bytes only; `dev-opaque-v1` is still an envelope.
- Sequence issuance locks one conversation row; never a global chat writer.
- `conversations.last_seq` and `messages.seq` are authoritative for ordering;
  `last_message_at` is inbox ordering only, never a sync cursor.
- Device-specific envelopes must belong to active, authorized devices.
- Private keys never reach the server; only public protocol material is stored.
- `asn_chat_web` contains transport code only. Domain rules live in contexts.

## Real-time

Phoenix Channels are reserved for live delivery and presence. REST/sync remains
the recovery path after reconnects; clients deduplicate on message ID. No channel
is registered in the scaffold yet.

## Tests

Coverage now includes pure unit tests for device changesets, event envelopes, and
JWT validation; real-PostgreSQL integration tests for accounts, device
lifecycle/outbox behavior, and the authenticated device API (401/403/503,
idempotent registration and revocation, ownership isolation, and the 256 KiB
body limit); and unboxed concurrent-registration/revocation race tests under
`test/failure/`. Remaining contexts add database-backed unit, integration, and
failure-path tests with their first implementation. Required failure paths are
listed in [`AGENTS.md`](../../AGENTS.md#7-verification).

## Related

- [Architecture and schema](../../docs/architecture/architecture-and-schema.md)
- [Development guide](../../docs/development/README.md)
- [ADR 0011 — Elixir and PostgreSQL baseline](../../docs/decisions/0011-elixir-and-postgres-baseline.md)
- [Contracts](../../contracts/README.md)
