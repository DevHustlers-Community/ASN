---
date: 2026-11-22
type: fix
scope: broker
summary: Inject a test clock into retention purge so fixture dates do not expire
breaking: false
adr: 0008
---

# Inject a test clock into retention purge

## Change

- `AsnEventBroker.Retention.purge/1` becomes `purge/2` with an optional `now`
  argument. Production callers, including the retention worker, keep using the
  real UTC clock with microsecond truncation. The second argument is documented
  as test-only: passing a future time would purge live rows.
- `test/integration/retention_test.exs` passes a fixed `@now_dt` through a local
  `purge/0` helper in all eleven purge calls. The "delivered deliveries purge
  after 24h" fixture was also moved to ten days old so the event-log floor is
  actually crossed; its previous date was only five days before `@now`.
- Updated the retention worker comment to refer to `purge/1` and `purge/2`.
- Removed the unused dev-only `tidewave` dependency that was present in the
  working tree but unrelated to this fix; `mix.lock` no longer carries it or
  its transitive entries.

## Why

The retention tests described `2026-10-15` as "ten days old" relative to a
fixed `@now` of `2026-10-25`, while `Retention.purge/1` compared against the
real wall clock. After `2026-11-14` those rows were past the 30-day terminal
window, so two tests failed even though broker behavior was correct. Freezing
the clock in the test removes the dependency on the date the suite is run.

## Verification

- `mix format --check-formatted` — clean
- `mix compile --warnings-as-errors` — clean
- `mix test` — 105 tests pass against local PostgreSQL 18.6

## Follow-ups

- Failure-path e2e cases (duplicate, out-of-order, broker restart, consumer
  lag) remain open per the broker README.
