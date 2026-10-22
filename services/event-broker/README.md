# Event broker

Custom Elixir/OTP event broker persisted in `broker_db`. It is not a wrapper
around NATS, Kafka, RabbitMQ, or another broker.

**Status:** scaffolded OTP service. It compiles, boots, and connects to
PostgreSQL, but it has no event schemas, migrations, transport, or delivery
logic yet. Transport (HTTP polling vs persistent connection), retention, and
limits remain open in [ADR 0008](../../docs/decisions/README.md).

**Owns:** the durable event log, subscription definitions, delivery attempts and
leases, acknowledgements, retry state, dead letters, and retention.

**Does not own:** any social, chat, or moderation entity. The producing service
database remains the source of truth.

## Stack

| Component | Baseline |
|---|---|
| Elixir / OTP | 1.20.4 / 29.1.2, pinned in [`.tool-versions`](../../.tool-versions) |
| Persistence | Ecto 3.14 / Ecto SQL 3.14 / Postgrex 0.22 |
| Database | PostgreSQL 18.6 locally via [`compose.yaml`](../../compose.yaml) |
| HTTP / Phoenix | Not included; the broker starts as a plain OTP application |

The OTP application is `:asn_event_broker`; the root module is
`AsnEventBroker`.

## Code map

See [`CODE_MAP.md`](CODE_MAP.md) for the planned subsystems and dependency
rules.

| Path | Responsibility |
|---|---|
| `lib/asn_event_broker/application.ex` | Root supervision tree; starts the repo |
| `lib/asn_event_broker/repo.ex` | The only Ecto boundary for `broker_db` |
| `config/` | Compile-time configuration plus dev/test/prod/runtime split |
| `priv/repo/migrations/` | Broker-owned migrations; intentionally empty |
| `test/support/` | Database test case and sandbox helper |

## First-release scope

1. Authenticate publishers and consumers with service credentials.
2. Validate envelope, schema version, and payload size.
3. Persist events and fan out to eligible durable subscriptions.
4. Lease deliveries with a visibility timeout and lease renewal.
5. Ack/nack, bounded exponential backoff, and dead-letter inspection/replay.
6. At-least-once delivery with per-aggregate in-flight limits (no global order).
7. Idempotent publish on `event_id`.
8. Health checks, metrics, structured logs, and an inspection API.
9. Crash/restart, database-disconnect, duplicate-delivery, and replay tests.

**Explicit non-goals for v1:** exactly-once delivery, clustering, partition
leadership, a custom disk log, and a custom wire protocol. Single-node
correctness is measured before any of these is considered.

## Planned layout (`lib/asn_event_broker/`)

| Subsystem | Responsibility |
|---|---|
| `events/` | Event envelope and canonical schema handling |
| `publishing/` | Idempotent publish and durable append |
| `subscriptions/` | Subscription definitions and filters |
| `routing/` | Fan-out selection per aggregate |
| `delivery/` | Leases, visibility timeout, in-flight limits |
| `acknowledgements/` | Ack/nack and lease completion |
| `retries/` | Bounded exponential backoff |
| `dead_letter/` | Dead-letter inspection and replay |
| `retention/` | Time/size retention and purge |
| `storage/postgres/` | PostgreSQL queries and transactions |
| `workers/` | Supervised delivery/retry/retention processes |
| `security/` | Service credentials and authorization |
| `telemetry/` | Metrics, logs, and traces |

These directories are created when their first implementation lands.

## Local development

From the repository root:

```bash
cp .env.example .env
docker compose up -d postgres
cd services/event-broker
mix deps.get
mix ecto.create
mix ecto.migrate
mix test
```

The broker has no listener yet. Running `mix run --no-halt` starts the OTP
application and repo, then waits. The HTTP or persistent-connection endpoint is
added only after ADR 0008.

Verification loop:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

## Configuration

| Variable | Used by | Notes |
|---|---|---|
| `BROKER_DATABASE_URL` | dev, prod | Full Ecto URL; dev default points at `broker_db` |
| `BROKER_TEST_DATABASE_URL` | test | Dev default points at `broker_db_test` |
| `POOL_SIZE` | prod | Ecto pool size, default `10` |

`BROKER_BASE_URL`, `BROKER_SERVICE_TOKEN`, and `EVENT_BROKER_PORT` in
[`.env.example`](../../.env.example) are reserved for the transport layer and are
not read by the scaffold.

## Boundaries

- Only the broker reads or writes `broker_db`. No business service gets a
  connection string to it.
- The broker does not validate business fields or read producer databases.
- Delivery is at-least-once; consumers deduplicate on `event_id` and reject stale
  updates with `aggregate_version`.
- Ordering is per aggregate only. There is no global event order.
- Transport code lives at the edge. Storage and delivery code must not depend on
  Phoenix, Plug, or Bandit.

## Tests

Current coverage verifies that the OTP application is defined. Database-backed
delivery, retry, dead-letter, and restart tests are added with the event schema
and storage implementation. Required failure paths are listed in
[`AGENTS.md`](../../AGENTS.md#7-verification).

## Related

- [Architecture and schema](../../docs/architecture/architecture-and-schema.md)
- [Development guide](../../docs/development/README.md)
- [ADR 0011 — Elixir and PostgreSQL baseline](../../docs/decisions/0011-elixir-and-postgres-baseline.md)
- [Broker operations](../../infrastructure/event-broker/README.md)
