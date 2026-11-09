---
date: 2026-11-09
type: fix
scope: chat-events
summary: Align the Chat outbox with typed event columns and harden relay status handling
breaking: false
adr: 0015
contracts: -
---

# Align the Chat outbox with typed event columns and harden relay status handling

## Change

- Added [ADR 0015](../../docs/decisions/0015-outbox-event-storage.md): the
  outbox row is the event (`id` is the event id), typed event fields replace the
  full `envelope` copy, `trace_id` is text, `occurred_at` is stored at
  microsecond precision, and constraints/indexes make the ADR 0008 ordering and
  uniqueness rules database invariants.
- Corrected architecture §3.18 and the ADR index with the resulting columns,
  indexes, and constraints.
- Added
  [`20261109000001_align_outbox_events.exs`](../../services/chat-service/priv/repo/migrations/20261109000001_align_outbox_events.exs):
  adds `type`, `schema_version`, `occurred_at`, `trace_id`, and `payload`,
  backfills them from existing envelopes, sets `id = event_id`, drops
  `event_id`, `envelope`, and `updated_at`, and installs the check constraints,
  partial unique index, and unpublished batch index. `down/0` reconstructs the
  previous schema and envelopes.
- Added [`AsnChat.Events.Envelope`](../../services/chat-service/lib/asn_chat/events/envelope.ex)
  to rebuild the publish envelope from a stored row, omitting absent optional
  fields and rendering `occurred_at` at six-digit precision.
- Reworked [`AsnChat.Events.Outbox`](../../services/chat-service/lib/asn_chat/events/outbox.ex)
  to write typed columns, validate the envelope shape (required fields, event
  and aggregate type patterns, versions, all-or-none aggregate fields, object
  payload, no unknown fields), map the database constraints to changeset errors,
  order unpublished work per aggregate, and mark rows published by `id`.
- Reworked [`AsnChat.Events.Relay`](../../services/chat-service/lib/asn_chat/events/relay.ex)
  to publish the rebuilt envelope and classify responses: 200/201 accepted;
  408/425/429/5xx and transport errors retried; 400/401/403/404/409/413/422 and
  any other unexpected status halt the remaining events of that aggregate with
  a critical log instead of crashing. A failure on one aggregate no longer
  blocks unrelated aggregates.
- Updated the Chat service [README](../../services/chat-service/README.md) and
  [CODE_MAP](../../services/chat-service/CODE_MAP.md) to describe the aligned
  outbox and the now-present unit and integration test layers.

## Why

Every Chat context writes through the outbox, so its shape had to be settled
before the first business context landed. The previous table duplicated the
payload inside a full envelope blob, had two identifiers for one event, and
omitted `occurred_at` from the recommended columns, which made a deterministic
envelope rebuild impossible. The relay also crashed on any status it did not
recognize and retried statuses that can never succeed.

## Verification

- `cd services/chat-service && mix format --check-formatted` — OK.
- `mix compile --warnings-as-errors` — OK.
- `mix test` against PostgreSQL 18.6 — 52 tests passed: envelope unit tests,
  outbox integration tests (typed storage, validation, aggregate uniqueness,
  ordering, transactional rollback, DB constraints, envelope round trip with
  the broker's canonical input), and relay integration tests (per-aggregate
  order and isolation, 200/201 acceptance, 409/422/4xx halts,
  408/425/429/5xx and transport retries, identical content on retry, unexpected
  statuses, aggregate-less events).
- Migration `up/0` → `down/0` → `up/0` on `chat_db_test`. Inserted a legacy
  envelope row between the rollback and the re-migration and confirmed the
  backfill produced `id = event_id`, UTC microsecond `occurred_at`, typed
  payload, and text `trace_id`; the rollback rebuilt an equivalent envelope.
- `psql \d outbox_events` confirms the check constraints, the partial unique
  aggregate index, and the `(created_at, id) WHERE published_at IS NULL` index;
  the superseded non-unique aggregate index is gone.
- `python3 scripts/ci/check-links.py` — OK.
- `python3 scripts/ci/check-changelog.py --all` — OK.

## Follow-ups

- The relay remains a single instance per service. Multiple instances need
  leader election or per-aggregate locking (ADR 0015 §8).
- Published-row retention and pruning are not implemented yet.
- Ecto still emits `timestamp without time zone` for `:utc_datetime_usec`; a
  repo-wide `timestamptz` alignment remains separate work.
