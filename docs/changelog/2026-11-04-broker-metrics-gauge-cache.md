---
date: 2026-11-04
type: perf
scope: broker
summary: Cache /metrics gauges so a scrape never queries the database
breaking: false
adr: 0008
contracts: -
---

# Cache /metrics gauges so a scrape never queries the database

## Change

- `services/event-broker/lib/asn_event_broker/web/metrics.ex`: the queue
  gauges (`pending`, `leased`, `dead`, `oldest_pending_seconds`) are now
  refreshed by the metrics process into a second ETS table
  (`:asn_event_broker_gauges`) and read from there by `render/0`. The
  scrape-time aggregate (`gauge_state/0`) still exists but runs only from
  `refresh/0`.
- Added public `refresh/0`. It runs in the caller, so a test can call it
  inside its sandbox checkout; the scheduled refresh calls it from the
  metrics process. A database error keeps the previous values and logs a
  warning instead of crashing the process (the counters live in its ETS
  table and would be lost).
- Added `config :asn_event_broker, :metrics, gauge_interval_ms: 5_000`
  (default). `config/test.exs` sets it to `0`, which disables the timer; the
  metrics process starts without a database checkout in the sandbox.
- Documented the cache and the interval in the service
  [`README`](../../services/event-broker/README.md#metrics-cache).

## Why

Issue #4: `/metrics` is unauthenticated and recomputed the gauges from
`deliveries` on every scrape, so any caller could turn a scrape into a scan of
the delivery table and hold a pool connection while it ran. Measured on
`broker_bench` with 1,000,000 deliveries, the gauge query takes 542 ms cold
and 118–124 ms warm; the issue's baseline recorded p95 26.3 ms per scrape at
100,000 rows. A 5 s cache keeps the values at most one interval stale while
making the scrape path O(counters) work only.

## Verification

- `mix format --check-formatted` — passed.
- `mix compile --warnings-as-errors` — passed.
- `mix test` — 88 passed (3 properties, 85 tests), against real PostgreSQL
  (`asn-postgres-1` healthy). New tests in
  `test/integration/metrics_test.exs`:
  - `render performs no database query`: attaches
    `[:asn_event_broker, :repo, :query]`, asserts `refresh/0` emits one query
    and `render/0` emits none;
  - `gauges reflect the last refresh, not the scrape-time database state`:
    seeds 1 pending + 1 leased + 1 dead delivery, calls `refresh/0`, asserts
    the exact rendered values, then shows a new pending delivery is invisible
    until the next `refresh/0` (1 → 2).
- Timing on `broker_bench` (1,000,000 deliveries, `MIX_ENV=dev`, workers and
  HTTP disabled): `refresh/0` 124.1 / 118.2 / 118.9 ms warm (542 ms on the
  first, cold, call); `render/0` 0.04 ms first call and 0.01 ms average over
  100 calls.
- Timer smoke test: booted the broker against `broker_bench` with the
  production interval, read `:asn_event_broker_gauges` after boot
  (`pending: 1000, leased: 1000, dead: 799000`), waited one interval and saw
  it refreshed again from the scheduled tick, without any scrape.
- `python3 scripts/ci/check-changelog.py --all` — passed.
- `python3 scripts/ci/check-links.py` — passed.

## Follow-ups

- The background refresh is still O(deliveries) (118 ms warm at 1M rows every
  5 s, ~2% of one pool connection average). If the table grows to tens of
  millions, raise `gauge_interval_ms` or add per-state partial indexes so the
  aggregate can use index-only scans; measure first.
