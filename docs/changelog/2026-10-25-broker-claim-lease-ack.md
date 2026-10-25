---
date: 2026-10-25
type: feat
scope: services
summary: Add claim/lease machinery, acknowledgements, backoff, and the lease reaper
breaking: false
adr: "0008"
contracts: -
---

# Add claim/lease machinery and acknowledgements

## Change

- Added `Delivery.claim/3`: long-poll claim (up to `long_poll_max_ms`, default
  20 s) with the ADR §6 ordering rule — only the earliest non-terminal
  delivery per `(subscription, aggregate_type, aggregate_id)` ordered by
  `aggregate_version` is claimable, so backoff and dead deliveries block
  later versions until an admin acts. Each attempt runs one short
  transaction: `FOR UPDATE` on the subscription row serializes claims, the
  per-subscription in-flight cap (10) is enforced, fresh random lease tokens
  are issued and stored hashed, and `attempts` increments at claim time.
- Added `Delivery.Waiters`: an in-process `:pg` wakeup registry — publishing
  wakes parked claims, a configurable fallback sweep (1 s) bounds missed
  wakeups, and no transaction or lock is held while parked.
- Added `Acknowledgements.ack/nack/extend`: exact lease-token semantics —
  current token + unexpired lease by database time; a delivered row keeps its
  final token hash so repeating the ack is an idempotent success; superseded
  tokens return `{:error, :stale_lease}` (409 at the edge). Nack transitions
  to `pending` with jittered exponential backoff scheduled from the actual
  attempts, or to `dead` when attempts are exhausted; errors are recorded on
  the row.
- Added `Retries` (bounded exponential backoff with full jitter, base 1 s,
  cap 5 min) and `Workers.LeaseReaper` (expired leases → pending or dead;
  logic in `reap/0`, scheduler disabled under the test sandbox).
- Delivery tuning values (lease 30 s, in-flight 10, attempts 5, sweep 1 s,
  reaper 5 s) moved to `config :asn_event_broker, :delivery` as runtime
  configuration, per ADR "defaults are configuration, not contract".
- Integration tests: head-of-line blocking, post-ack progression, concurrent
  claims leasing at most one, idempotent ack vs superseded token, expired
  lease behavior, nack backoff and dead-letter transitions, reaper paths,
  paused/unknown subscriptions, aggregate-less claiming, and publish waking
  parked claims before the sweep.

## Why

This completes the delivery core of ADR 0008: at-least-once with consumer-side
deduplication, per-aggregate ordering, and lease semantics — the state
machine recorded in the ADR is now executable and proven against real
PostgreSQL.

## Verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test` — run; 38/38 pass; `broker_db_test` verified empty after the
  suite (no sandbox leaks; concurrent tests share the sandbox owner via
  `Ecto.Adapters.SQL.Sandbox.allow/3`).
- `python3 scripts/ci/check-changelog.py --all` — run; pass.

## Follow-ups

- Dead-letter inspection/replay/skip with the audit log (phase 4),
  dependency-aware retention (phase 5), then the HTTP edge and auth with an
  OpenAPI contract first (phase 6).
