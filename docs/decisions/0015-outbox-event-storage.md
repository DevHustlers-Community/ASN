# 0015 - Outbox event storage columns

- Status: accepted
- Date: 2026-11-09
- Supersedes: -

## Context

The first Chat outbox migration stored the complete event envelope in a single
`envelope jsonb` column plus a separate `event_id`. The architecture document
(§3.18) recommends typed columns (`type`, `schema_version`, `payload`, and the
aggregate fields), but a re-check found that §3.18 was itself incomplete:

- it omitted `occurred_at`, which the envelope schema requires;
- it typed `trace_id` as `uuid`, while the envelope accepts a W3C trace id or a
  UUID;
- an index on `(created_at, id)` alone does not provide the per-aggregate
  ordering that ADR 0008 requires from the producer relay.

Every Chat domain context is about to write through this table, so its shape
must be settled before the first business context lands. Reworking it after
multiple contexts depend on it would be a persisted-format migration across
every write path.

## Decision

### 1. One row per event, `id` is the event id

`outbox_events.id` is the event id: a UUIDv7 minted in application code. There
is no separate `event_id` column. The envelope's `event_id` is the row `id`.

### 2. Store typed event fields, not a second envelope copy

`outbox_events` stores:

`(id uuid PK, type text NOT NULL, aggregate_type text, aggregate_id uuid, aggregate_version bigint, schema_version integer NOT NULL DEFAULT 1, occurred_at timestamptz NOT NULL, payload jsonb NOT NULL, trace_id text, created_at timestamptz NOT NULL, published_at timestamptz)`.

The relay rebuilds the full publish envelope from the row through
`AsnChat.Events.Envelope.from_outbox/1`. It does not store the envelope twice.

### 3. Timestamp handling

`occurred_at` is stored in UTC with microsecond precision. The broker normalizes
every `occurred_at` to microsecond precision before hashing the envelope, and
the rebuild uses the same precision. Because the relay always publishes from the
stored row, a retry after a restart serializes the same content and the broker's
content hash stays stable.

Ecto's `:utc_datetime_usec` currently emits `timestamp without time zone`; all
values are UTC. Aligning the whole schema to `timestamptz` is a separate,
repo-wide change and does not affect this decision.

### 4. `trace_id` is text

The envelope accepts either a UUID or a W3C trace id. A `uuid` column would
reject valid W3C trace ids, so the column is `text`.

### 5. Constraints

- `schema_version >= 1`.
- `aggregate_version >= 1` when present.
- Aggregate fields are all present or all absent.
- `payload` is a JSON object.
- A partial unique index on
  `(aggregate_type, aggregate_id, aggregate_version) WHERE aggregate_type IS NOT NULL`
  makes "exactly one event per aggregate version" a database invariant, matching
  ADR 0008. A reused version fails before it reaches the broker.

### 6. Indexes

- `(created_at, id) WHERE published_at IS NULL` for batch pickup and later
  retention pruning.
- `(aggregate_type, aggregate_id, aggregate_version) WHERE published_at IS NULL`
  for the relay's per-aggregate ordering guarantee.

### 7. Drop the unused `updated_at`

The outbox is append-only except for setting `published_at`. `created_at` and
`published_at` are enough; dropping `updated_at` removes a column that never
changes.

### 8. Relay concurrency

The relay remains a single instance per service. Running multiple relay
instances requires leader election or per-aggregate locking so two nodes cannot
publish versions out of order. That is a deployment constraint and a follow-up,
not part of this change.

## Consequences

- Chat contexts write typed fields and can query unpublished work, aggregate
  order, and retention without parsing JSON.
- The relay rebuild has one correctness-critical surface: every envelope field
  must be present. Unit and round-trip tests cover the field set and timestamp
  normalization.
- The migration is a one-step alignment because the project has no production
  data yet. After the first production deployment, persisted-format changes
  follow add, backfill, switch, remove across separate migrations.
- The broker remains the only component that computes the content hash; Chat
  stores the inputs and rebuilds them deterministically.

## Alternatives considered

- **Keep the full envelope blob.** Rejected: it duplicates the payload, makes
  unpublished-work and retention queries depend on JSONB expressions, and keeps
  the documented schema and the implementation apart.
- **Keep `event_id` beside `id`.** Rejected: two identifiers for one event add
  no information; the outbox row is the event.
- **Keep `trace_id uuid` from §3.18.** Rejected: it would reject W3C trace ids.
- **Store `occurred_at` as text.** Rejected: it loses time-zone-aware ordering
  and the broker already works with instants.
- **Use only `(created_at, id)` from §3.18.** Rejected: it does not encode the
  per-aggregate relay ordering required by ADR 0008.
