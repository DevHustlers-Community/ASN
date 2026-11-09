# Chat service code map

Companion to the [service README](README.md). This map describes ownership and
dependency direction; it is not a feature list.

## Rules

- `lib/asn_chat_web/` is transport code. It maps requests and channel events to
  context calls and renders responses. It does not contain business rules.
- `lib/asn_chat/` owns domain rules and persistence orchestration.
- Only `AsnChat.Repo` talks to `chat_db`. Contexts do not open ad-hoc
  connections or query another service's database.
- Contexts may call another context through its public API. They do not import
  another context's schema or private helpers.
- No plaintext chat content or private keys may appear in code, fixtures, logs,
  events, traces, or tests.

## Runtime root

| Path | Responsibility |
|---|---|
| `lib/asn_chat.ex` | Namespace for the domain application |
| `lib/asn_chat/application.ex` | Starts telemetry, repo, PubSub, and endpoint |
| `lib/asn_chat/repo.ex` | Ecto repo and `chat_db` boundary |

## Web layer

| Path | Responsibility |
|---|---|
| `lib/asn_chat_web.ex` | Shared `use` macros for JSON controllers and channels |
| `lib/asn_chat_web/endpoint.ex` | Bandit endpoint and request pipeline |
| `lib/asn_chat_web/router.ex` | Route registration only; versioned API scope |
| `lib/asn_chat_web/telemetry.ex` | Endpoint telemetry definitions |
| `lib/asn_chat_web/controllers/` | HTTP controllers and error rendering |
| `lib/asn_chat_web/channels/` | Planned Phoenix Channels for live delivery |

`router.ex` registers routes only. Controllers map input/output; contexts hold
rules; repositories hold queries; schemas validate input. Do not put sequence
allocation, membership checks, or envelope validation in a controller or channel.

## Domain contexts

| Context | Status | Owns | May depend on |
|---|---|---|---|
| `accounts/` | Implemented | `chat_users` projections and per-user lock | `repo`, `events` |
| `conversations/` | Planned | Conversations, membership, privacy, blocking projections | `accounts`, `blocks`, `events` |
| `messages/` | Planned | Envelope persistence, per-conversation sequence, edits, tombstones | `conversations`, `devices`, `crypto`, `events` |
| `attachments/` | Planned | Encrypted upload lifecycle and object keys | `conversations`, `messages`, `events` |
| `read_receipts/` | Planned | Read cursors and receipt state | `conversations`, `messages` |
| `devices/` | Implemented | Device registry; MLS KeyPackage storage (`device_key_packages`) is the next slice (ADR 0007) | `accounts`, `events` |
| `crypto/` | Planned | Protocol-neutral envelope validation and key-rotation triggers | `devices`, `messages` |
| `blocks/` | Planned | `chat_block_edges` projection and fail-closed checks | `accounts`, `events` |
| `delivery/` | Planned | Channel fan-out, presence, push dispatch | `conversations`, `messages`, `devices` |
| `events/` | Implemented | Transactional outbox writer, envelope rebuild, publisher relay, consumers | `repo`, domain contexts |

Contexts are added with their first schema, query, or rule. Do not commit empty
placeholder directories.

## Persistence

| Path | Responsibility |
|---|---|
| `priv/repo/migrations/` | Forward-only migrations owned by Chat |
| `priv/repo/seeds.exs` | Local seed entry point; currently no product seeds |

Migrations must include their indexes and constraints in the same change. Do not
create foreign keys to another service's database. Cross-database references are
soft references documented as `ref: <db>.<table>.<column>`.

## Tests

| Path | Responsibility |
|---|---|
| `test/asn_chat_web/` | Controller, endpoint, and channel tests |
| `test/support/conn_case.ex` | Connection and sandbox setup |
| `test/support/data_case.ex` | Database and sandbox setup |
| `test/support/chat_fixtures.ex` | User and device fixtures |
| `test/unit/` | Pure module tests, for example device changesets and envelope rebuild |
| `test/integration/` | Real-PostgreSQL tests, for example outbox, relay, accounts, and devices |
| `test/failure/` | Concurrency and failure-path tests; device races use `unboxed_run/2` |

Integration tests use the real local PostgreSQL database. E2EE tests use fixed
envelope vectors and never plaintext fixtures.

Race tests intentionally bypass the SQL sandbox because two processes need
separate connections to contend on the same `chat_users` row. They clean up their
own rows and must not use `AsnChat.DataCase`.

## Change checklist

1. Update the OpenAPI or event contract before the code when a contract changes.
2. Add the migration and constraints with the owning context.
3. Keep authorization server-side and out of the client.
4. Add unit, integration, and failure-path coverage.
5. Run the commands in the [README](README.md#local-development).
6. Add a change record under [`docs/changelog/`](../../docs/changelog/README.md).
