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

## Domain contexts (planned)

| Context | Owns | May depend on |
|---|---|---|
| `accounts/` | `chat_users` projections | `repo`, `events` |
| `conversations/` | Conversations, membership, privacy, blocking projections | `accounts`, `blocks`, `events` |
| `messages/` | Envelope persistence, per-conversation sequence, edits, tombstones | `conversations`, `devices`, `crypto`, `events` |
| `attachments/` | Encrypted upload lifecycle and object keys | `conversations`, `messages`, `events` |
| `read_receipts/` | Read cursors and receipt state | `conversations`, `messages` |
| `devices/` | Device registry and public prekey material | `accounts`, `events` |
| `crypto/` | Protocol-neutral envelope validation and key-rotation triggers | `devices`, `messages` |
| `blocks/` | `chat_block_edges` projection and fail-closed checks | `accounts`, `events` |
| `delivery/` | Channel fan-out, presence, push dispatch | `conversations`, `messages`, `devices` |
| `events/` | Transactional outbox writer, publisher, consumers | `repo`, domain contexts |

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
| `test/unit/`, `test/integration/`, `test/failure/` | Planned layers as contexts land |

Integration tests use the real local PostgreSQL database. E2EE tests use fixed
envelope vectors and never plaintext fixtures.

## Change checklist

1. Update the OpenAPI or event contract before the code when a contract changes.
2. Add the migration and constraints with the owning context.
3. Keep authorization server-side and out of the client.
4. Add unit, integration, and failure-path coverage.
5. Run the commands in the [README](README.md#local-development).
6. Add a change record under [`docs/changelog/`](../../docs/changelog/README.md).
