---
date: 2026-10-26
type: feat
scope: services
summary: Add chat_db transactional outbox and the broker relay with the producer ordering contract
breaking: false
adr: "0008"
contracts: -
---

# Add the chat outbox and broker relay

## Change

- Added `chat_db` migration `outbox_events`: committed envelopes (never
  plaintext chat content) with per-aggregate columns and a partial index over
  unpublished rows in aggregate-version order.
- Added `AsnChat.Events.Outbox`: `record/1` is called inside the same
  transaction as the chat business change (transactional outbox, architecture
  §2); `unpublished/1` returns rows in per-aggregate version order;
  `mark_published/1` closes the loop after broker acceptance.
- Added `AsnChat.Events.Relay` implementing the ADR 0008 §5 producer relay
  contract: publish version N, advance to N+1 only after definitive
  acceptance (201/200); retry the same `event_id` with identical content on
  timeouts; a 409/422 is a producer bug — the relay halts the batch and
  alerts instead of skipping. The HTTP client is injectable; the default
  posts to `BROKER_BASE_URL/v1/events` with `BROKER_SERVICE_ID` /
  `BROKER_SERVICE_TOKEN` and `BROKER_PUBLISH_TIMEOUT_MS`.
- The relay joins the chat supervision tree behind
  `config :asn_chat, :events_relay` (disabled under the test sandbox).
- Relay tests with an injected client: acceptance marks rows published,
  advancement stops on non-acceptance with the same event_id retried next
  tick, a 409 halts without attempting later versions, and timeout ambiguity
  leaves rows unpublished for identical-content retry.

## Why

This closes the producer side of the event flow: chat commits a business
change and its envelope atomically, and the relay delivers it to the broker
under the ordering contract the external reviews required to be enforceable.

## Verification

- `mix ecto.migrate` — applied to `chat_db_test` (and `chat_db`).
- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test` — run; 6/6 pass (existing chat suite plus relay tests).
- The broker-side contract this relay speaks is proven by the broker's own
  suite (publish 201/200/409/422 and claim flows). A true two-process
  end-to-end run (relay → live broker) lands with the `tests/` harness.

## Follow-ups

- Cross-service end-to-end harness under `tests/` (relay against a live
  broker) once the shared test infrastructure exists.
- Wire real chat features (device registration, receipts) to record their
  envelopes through `Outbox.record/1` inside their transactions.
