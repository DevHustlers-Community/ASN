# Event broker code map

Companion to the [service README](README.md). The broker is transport-neutral
until [ADR 0008](../../docs/decisions/README.md) selects a delivery transport.

## Rules

- Only `AsnEventBroker.Repo` talks to `broker_db`.
- The broker never reads or writes a producer or consumer database.
- Storage and delivery code must not depend on Phoenix, Plug, or Bandit.
- A transport adapter may call the broker's public API. It may not contain
  routing, lease, retry, or retention rules.
- Event payloads are opaque to the broker beyond envelope validation. It must not
  persist plaintext chat content.

## Runtime root

| Path | Responsibility |
|---|---|
| `lib/asn_event_broker.ex` | Namespace and public entry points |
| `lib/asn_event_broker/application.ex` | Root supervision tree |
| `lib/asn_event_broker/repo.ex` | Ecto repo and `broker_db` boundary |

## Planned subsystems

| Path | Responsibility | May depend on |
|---|---|---|
| `events/` | Envelope structure and canonical validation | `repo`, `telemetry` |
| `publishing/` | Idempotent publish on `event_id` | `events`, `storage/postgres`, `subscriptions`, `routing` |
| `subscriptions/` | Durable subscription definitions and filters | `repo` |
| `routing/` | Eligible subscriber selection per aggregate | `subscriptions`, `storage/postgres` |
| `delivery/` | Leases, visibility timeout, in-flight limits | `routing`, `storage/postgres`, `workers` |
| `acknowledgements/` | Ack/nack and terminal delivery state | `delivery`, `storage/postgres` |
| `retries/` | Bounded exponential backoff and scheduling | `delivery`, `storage/postgres` |
| `dead_letter/` | Dead-letter inspection and replay | `events`, `publishing`, `storage/postgres` |
| `retention/` | Time and size retention, purge | `storage/postgres` |
| `storage/postgres/` | Queries, transactions, and row locking | `repo` |
| `workers/` | Supervised delivery, retry, and retention processes | All domain subsystems |
| `security/` | Service credentials and authorization | `repo`, `telemetry` |
| `telemetry/` | Metrics, logs, and traces | None |

Subsystem directories are added with their first implementation. Do not commit
empty placeholder directories.

## Transport boundary

The transport decision is open. The scaffold deliberately contains no HTTP
adapter, endpoint, router, or listener. When ADR 0008 lands:

- Add the adapter as a separate supervised component.
- Keep authentication and request validation at the adapter boundary, delegating
  to `security/` and `publishing/`.
- Keep delivery leases and acknowledgements independent of the transport.
- Do not change event contracts as part of an adapter-only change.

## Persistence

| Path | Responsibility |
|---|---|
| `priv/repo/migrations/` | Forward-only broker migrations |

The event log, subscriptions, delivery leases, acknowledgements, retry state,
dead letters, and retention metadata are broker-owned. No business service sees
`broker_db`.

## Tests

| Path | Responsibility |
|---|---|
| `test/support/data_case.ex` | Database test case and sandbox setup |
| `test/unit/`, `test/integration/`, `test/failure/` | Planned layers as subsystems land |

Required failure paths include duplicate publish, duplicate delivery,
out-of-order delivery per aggregate, broker restart with in-flight leases,
database disconnect, consumer lag, dead-letter replay, and retention purge.

## Change checklist

1. Update the event contract before the code when an envelope or subscription
   contract changes.
2. Add the migration and constraints with the owning subsystem.
3. Prove idempotency and at-least-once behavior in a real PostgreSQL test.
4. Run the commands in the [README](README.md#local-development).
5. Add a change record under [`docs/changelog/`](../../docs/changelog/README.md).
