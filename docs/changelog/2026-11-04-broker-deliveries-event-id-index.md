---
date: 2026-11-04
type: perf
scope: broker
summary: Index deliveries by event_id for the retention purge and its FK checks
breaking: false
adr: 0008
contracts: -
---

# Index deliveries by event_id for the retention purge and its FK checks

## Change

- Added `services/event-broker/priv/repo/migrations/20261104120000_add_deliveries_event_id_index.exs`:
  forward-only `create index(:deliveries, [:event_id])`. The initial migration
  is untouched. No query, schema, or API behavior changes.
- Recorded the measurements below and the unmet second acceptance criterion so
  the remaining work on issue #2 is explicit.

## Why

Issue #2: retention deletes events with a correlated `NOT EXISTS` against
`deliveries`, and `events` is the parent of `deliveries` with
`ON DELETE RESTRICT`. No index had `event_id` as its leading column: the unique
`(subscription_id, event_id)` index can only serve a lookup that already knows
the subscription, so both the `NOT EXISTS` probe and the per-row
`ON DELETE RESTRICT` check had to scan something much larger than one event's
deliveries.

## Verification

- `mix format --check-formatted` — passed.
- `mix compile --warnings-as-errors` — passed.
- `mix test` — 87 passed (84 tests, 3 properties), including
  `RetentionTest`/`DeadLetterTest`, against real PostgreSQL
  (`asn-postgres-1` healthy). `mix test` runs `ecto.migrate` on
  `broker_db_test`, so the new migration is exercised.
- Seeded `broker_bench` (PostgreSQL 18.6) with 100,000 events all older than
  the 7-day event floor, 1,000,000 deliveries across 10 subscriptions
  (799,000 dead inside the 30-day window, 199,000 delivered 3 days ago,
  1,000 leased, 1,000 pending). `ANALYZE` after loading; seed SQL kept outside
  the repository.
- `ON DELETE RESTRICT` check (`SELECT 1 FROM ONLY deliveries x WHERE
  x.event_id = ... FOR KEY SHARE`):
  - before: `Index Scan using deliveries_subscription_id_event_id_index`,
    8.17 ms, 79 shared buffers (a full scan of the 801k-entry composite
    index, filtered on its second column);
  - after: `Bitmap Index Scan on deliveries_event_id_index`, 0.22 ms, 5 shared
    buffers.
- `EXPLAIN (ANALYZE, BUFFERS)` of `@purge_events_sql` with batch `1000`,
  preceded by the same `deliveries` delete that `Retention.purge/1` performs
  first, on 801,000 remaining delivery rows. Warm samples, before → after:
  - `Trigger for constraint deliveries_event_id_fkey` (1000 calls):
    192.3 ms / 189.5 ms → 99.6 ms / 70.7 ms / 96.1 ms;
  - statement total: 1141 ms / 656 ms → 695 ms / 542 ms / 432 ms. One cold
    sample each: 2277 ms → 695 ms.
- Not met: the second acceptance criterion ("EXPLAIN of `@purge_events_sql`
  shows an index lookup on `deliveries(event_id)`"). The anti-join plan is
  unchanged — `Hash Right Anti Join` over `Seq Scan on deliveries` before and
  after — because the planner must prove the absence of a blocking delivery
  for essentially every candidate event, so the probe is executed once per
  retained delivery row regardless of the index. At this shape the index
  changes the FK check, not the anti-join scan.
- `python3 scripts/ci/check-changelog.py --all` — passed.
- `python3 scripts/ci/check-links.py` — passed.

## Follow-ups

- The anti-join still scans `deliveries` once per purge call. Measured
  experiment: a covering
  `(event_id) INCLUDE (state, delivered_at, dead_lettered_at, skipped_at)`
  index did **not** change the plan and made the FK probes slower (wider
  index), so it was not adopted. Reducing the anti-join scan needs a different
  change (query shape with a bounded candidate set, or a persistent
  "blocked" flag), which changes retention semantics and belongs in its own
  issue/ADR.
- The index is built without `CONCURRENTLY`; the deploy story does not run
  migrations outside a transaction yet.
