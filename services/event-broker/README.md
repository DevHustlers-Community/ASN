# Event broker

Custom Elixir/OTP event broker persisted in `broker_db`. It is not a wrapper
around NATS, Kafka, RabbitMQ, or another broker.

**Owns:** the durable event log, subscription definitions, delivery attempts and
leases, acknowledgements, retry state, dead letters, and retention.

**Does not own:** any social, chat, or moderation entity. The producing service
database remains the source of truth.

**First-release scope:**

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

**Planned layout (`lib/asn_event_broker/`):** `events/`, `publishing/`,
`subscriptions/`, `routing/`, `delivery/`, `acknowledgements/`, `retries/`,
`dead_letter/`, `retention/`, `storage/postgres/`, `workers/`, `security/`,
`telemetry/`.

**Status:** not scaffolded. Transport (HTTP polling vs persistent connection),
retention windows, and limits are ADR decisions.
