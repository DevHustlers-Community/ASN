# Chat service

Elixir + Phoenix + Ecto service that owns `chat_db`.

**Status:** scaffolded API-only service. The service compiles, boots, and connects
to PostgreSQL, but it has no product endpoints, contexts, or migrations yet.
Persisted envelope formats remain blocked by the E2EE decisions in
[ADR 0007](../../docs/decisions/README.md) and
[ADR 0009](../../docs/decisions/README.md).

**Owns:** friendships, chat privacy settings, direct and community
conversations, conversation membership, opaque message envelopes, public device
identity/prekey material, media upload tracking, receipts, push devices, and chat
streaks.

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
the planned contexts.

| Path | Responsibility |
|---|---|
| `lib/asn_chat/application.ex` | Supervision tree: telemetry, repo, PubSub, endpoint |
| `lib/asn_chat/repo.ex` | The only Ecto boundary for `chat_db` |
| `lib/asn_chat_web.ex` | JSON controller and channel helpers |
| `lib/asn_chat_web/endpoint.ex` | Bandit endpoint and request pipeline |
| `lib/asn_chat_web/router.ex` | Empty `/api` scope; no routes yet |
| `lib/asn_chat_web/telemetry.ex` | Endpoint telemetry |
| `config/` | Compile-time configuration plus dev/test/prod/runtime split |
| `priv/repo/migrations/` | Chat-owned migrations; intentionally empty |
| `test/` | ExUnit tests and ConnCase/DataCase support |

## Planned contexts (`lib/asn_chat/`)

| Context | Purpose |
|---|---|
| `accounts/` | `chat_users` projections |
| `conversations/` | Direct/community conversations, membership, privacy |
| `messages/` | Sequence issuance, envelopes, edits, tombstones |
| `attachments/` | Encrypted upload lifecycle |
| `read_receipts/` | Read cursors and receipts |
| `devices/` | Device registry and public prekeys |
| `crypto/` | Protocol state, key rotation triggers, envelope validation helpers |
| `blocks/` | `chat_block_edges` projection and fail-closed checks |
| `delivery/` | Channel fan-out, push, presence |
| `events/` | Outbox writer, publishers, consumers |

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

The API listens on `http://localhost:4002` but has no routes yet. Run the
verification loop with:

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

Current coverage is the generated error-rendering test. Database-backed unit,
integration, and failure-path tests are added with each context. Required failure
paths are listed in [`AGENTS.md`](../../AGENTS.md#7-verification).

## Related

- [Architecture and schema](../../docs/architecture/architecture-and-schema.md)
- [Development guide](../../docs/development/README.md)
- [ADR 0011 — Elixir and PostgreSQL baseline](../../docs/decisions/0011-elixir-and-postgres-baseline.md)
- [Contracts](../../contracts/README.md)
