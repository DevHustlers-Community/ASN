---
date: 2026-10-27
type: fix
scope: broker
summary: Fix retention cutoffs, audit atomicity, metrics cost, and DB-time lease checks
breaking: false
adr: 0008
contracts: contracts/openapi/event-broker-api.yaml
---

# Fix retention cutoffs, audit atomicity, metrics cost, and DB-time lease checks

## Change

- Retention event purge now compares delivered deliveries against the 24-hour
  delivered cutoff and dead/skipped deliveries against the 30-day terminal
  cutoff, so events backing live dead letters survive the full replay window.
- Credential revocation and subscription PATCH write their audit entry in the
  same transaction as the state change.
- The OpenAPI contract documents 400 Problem Details for claim, ack, nack,
  extend, skip, inspection, replay, and credential issue, plus the
  500-character `last_error_message` bound and the 200-row inspection limit.
  Revocation no longer advertises a 400 it cannot return.
- Metrics scrape uses one FILTER-aggregate query, reports the oldest pending
  delivery with `min(created_at)`, escapes Prometheus labels in the correct
  order, and detaches a handler whose ETS table has disappeared.
- The waiter registry tolerates an already-started `:pg` scope.
- Ack, nack, extend, and claim compare lease and due times against database
  time instead of a client-supplied timestamp, and write lease expiry and the
  nack backoff schedule from the database clock.
- Nack, replay, and skip now emit their telemetry counters; rejected invalid
  envelopes emit `[:publish, :rejected]` with reason `:invalid_envelope`.
- Added forward-only partial indexes for retention purges and event receipt.
- Bumped Bandit from 1.13 to 1.14 in the same batch.

## Why

The event purge reused the terminal cutoff for delivered deliveries, delaying
delivery purge eligibility by up to 30 days. Several audit writes could commit
independently of the change they describe. Lease comparisons trusted client
clocks, and the metrics scrape paid for four separate aggregate queries.

## Verification

- `mix format --check-formatted` — passed.
- `mix compile --warnings-as-errors` — passed.
- `mix ecto.migrate` — applied `20261027120000_add_broker_purge_claim_indexes`.
- `mix test` — 84 passed (3 properties, 81 tests).
- `python3 scripts/ci/check-changelog.py --all` — passed.
- `python3 scripts/ci/check-links.py` — passed.

## Follow-ups

- None.
