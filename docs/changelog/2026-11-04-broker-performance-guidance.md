---
date: 2026-11-04
type: docs
scope: event-broker
summary: Document broker pool sizing and load-test guidance
breaking: false
adr: -
contracts: -
---

# Document broker pool sizing and load-test guidance

## Change

- [`services/event-broker/README.md`](../../services/event-broker/README.md):
  new **Performance** section with three parts:
  - **Connection pool sizing** — what `POOL_SIZE` covers (publish, claim, and ack
    transactions, plus background workers), why parked long-poll consumers do
    not hold connections across the wait, the error (`DBConnection.ConnectionError`)
    that pool queueing produces, and why batching claims and bounding ack
    concurrency come before raising the default.
  - **Running the harness safely** — the `bench-` prefix boundary, the
    `--allow-nonlocal` refusal, the rule that B7 must never run with
    `--allow-shared-db` against a shared database, the dedicated `broker_bench`
    path, token requirements, single-invocation rule, and the reduced-size first
    run.
  - **Recorded results and decisions** — a dated summary table linking every
    claim to the measured numbers in the baseline document.
- The section links to
  [`docs/performance/broker-baseline.md`](../../docs/performance/broker-baseline.md)
  for the full scenario definitions, commands, environments, and detailed
  tables.

## Why

Issue #13. The broker's performance evidence already lived in the baseline
document, but the README had no single entry point for operators: pool sizing
was only mentioned inside the long-poll and batched-claim notes, and the safety
rules for B7 were only in the baseline document. The baseline showed pool
exhaustion at 50 parked consumers with `pool_size: 10` before the idle-sweep
fix, which made "size the pool" easy to misread as "raise the default".

## Verification

- Every number in the new section is copied from
  [`docs/performance/broker-baseline.md`](../../docs/performance/broker-baseline.md):
  - B5 before: 135 claim requests, 46 errors (34%), 18,294 statements over
    50.18 s.
  - B5 after: 0 errors, 2,216 statements over 40.12 s (~1.1/s per consumer), 0
    `FOR UPDATE`.
  - B6 2026-11-02: 10,000 rows in 145.69 s (68.64/s).
  - B6 2026-11-04: 10,000 rows in 148.71 s at cap 100 (67.25/s), claim 7.43 ms;
    SQL-only drain 4,463/s.
  - B7 2026-11-02: 60,000 rows purged in 2,615 ms (~22,900 rows/s),
    `allow_shared_db: false`.
  - B8 2026-10-28: `/metrics` p95 26.3 ms at 100k rows, before the gauge cache.
- `python3 scripts/ci/check-links.py` and `python3
  scripts/ci/check-changelog.py --all` → pass.
- No production code changed: only the broker README and this record.

## Follow-ups

- Re-run B6 at 100k and 1M rows after ack batching lands; the baseline notes the
  harness ack loop as the current bottleneck.
- Re-run B7 at full size once the retention decisions are settled.
