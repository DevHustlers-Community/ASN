---
date: 2026-11-04
type: perf
scope: broker
summary: Lease a whole claim batch with one UPDATE instead of one UPDATE per row
breaking: false
adr: 0008
contracts: -
---

# Lease a whole claim batch with one UPDATE

## Change

- `services/event-broker/lib/asn_event_broker/delivery.ex`:
  - `@claim_sql` is now one statement: a `candidates` CTE selects up to the
    batch size from the pending head of each aggregate, a `numbered` CTE
    assigns each candidate a slot, and one `UPDATE ... FROM ... RETURNING`
    leases the batch. Each delivery still gets its own lease token: the caller
    passes the SHA-256 hashes as a `text[]` and the statement indexes it by the
    candidate's slot.
  - Candidate selection no longer sorts the subscription's whole pending
    backlog. There is no global `ORDER BY` because ADR 0008 §6 guarantees
    ordering per aggregate only; the existing anti-join still picks exactly the
    earliest non-terminal version of each aggregate.
  - `FOR UPDATE SKIP LOCKED` is not used. The `SELECT` takes no row locks, and
    the subscription-row `FOR UPDATE` lock already serializes claimers of one
    subscription. ADR 0008 §6 records `SKIP LOCKED` as an alternative to adopt
    only after contention is measured, not speculatively.
  - `lease_batch/4` (per-row recursion) became `lease_batch/2` (one statement);
    `claimed_map/3` maps the returned slot to the caller's token.
- [`services/event-broker/README.md`](../../services/event-broker/README.md#batched-claims):
  new "Batched claims" subsection.
- [`docs/performance/broker-baseline.md`](../performance/broker-baseline.md):
  B6 before/after measurements.

## Why

Issue #9. The old claim loop ran one `UPDATE` per delivery inside the
subscription lock, and every one of those statements evaluated the anti-join
and sorted all pending rows for the subscription. At 100,000 pending rows a
single claim of one row took **748.6 ms** (`EXPLAIN ANALYZE`: sequential scan
of 100,000 rows, external merge sort of 3,136 kB). A drain therefore got slower
as the backlog grew: B6 at 10,000 rows managed 46.17/s, and the 100,000-row
attempt exceeded its timeout.

One statement per batch removes both the per-row statement overhead and the
repeated sort. ADR 0008 §6 already says there is no global ordering, so the
global `ORDER BY` was not a contract; per-aggregate ordering remains enforced
by the anti-join and by `deliveries_one_leased_per_aggregate`.

## Verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors` — passed.
- `mix test` — 99 passed (3 properties, 96 tests). Re-ran with seeds 1, 2, and
  3 — 99 passed each time. New tests:
  - a claim leases its whole batch in one `UPDATE` statement with distinct
    tokens;
  - a batch never leases two versions of one aggregate;
  - a `max=100` claim returns exactly 100 rows when available, stops at the
    in-flight cap, and returns the rest after acks;
  - a full 100-row batch over 100 aggregates leases only version 1 of each.
- B6 on a dedicated `broker_b6` database (PostgreSQL 18.6, `pool_size: 10`,
  Bandit 1.14.0), 10,000 pending rows, one consumer:

  | Run | cap | Drain | Batches | Claim SQL from the broker log |
  |---|---|---|---|---|
  | before (`upstream/main`) | 10 | 216.60 s (46.17/s) | 1,000 | 38,696 ms / 10,001 statements (3.87 ms avg) |
  | after | 10 | 169.72 s (58.92/s) | 1,000 | 2,458 ms / 1,001 statements (2.46 ms avg) |
  | after | 100 | 148.71 s (67.25/s) | 100 | 750 ms / 101 statements (7.43 ms avg) |

  Claim time is Ecto's `db=` time from the broker's `QUERY OK` log, summed by
  statement. The end-to-end gain is smaller than the claim gain because B6
  acks one delivery per HTTP request and each ack is its own transaction
  (~10 ms of commit/flush): 10,000 acks dominate the wall clock in every run.
- Claim statement at 100,000 pending rows (`EXPLAIN ANALYZE`, same database):
  - old one-row statement: 748.6 ms (100,000-row sequential scan, 3,136 kB
    external merge sort);
  - new 100-row statement: 6.4 ms (sequential scan stops after the `LIMIT`
    100, 100 primary-key updates).
- One-million-row table (990,000 delivered + 10,000 pending): the new 100-row
  claim takes 12.0 ms and uses
  `deliveries_subscription_id_next_attempt_at_index` (100-row index scan), so
  a mostly-terminal table does not fall back to a sequential scan.
- SQL-only drain of 100,000 pending rows in `broker_b6` (claim batches plus a
  bulk ack per batch, one transaction): 100,000 rows in 22,406 ms (4,463/s,
  1,000 batches).
- `bash tests/e2e/broker-relay.sh` — passed.
- `python3 scripts/ci/check-changelog.py --all`,
  `python3 scripts/ci/check-links.py` — passed.

## Not run

- B6 end-to-end at 100,000 rows: the harness acks each delivery in its own
  HTTP request and transaction, so 100,000 acks alone cost roughly 17 minutes
  at the measured ~10 ms per ack. The claim path was measured directly at that
  size instead (above). B6 at 1,000,000 rows remains out of reach for the same
  reason until the ack path is batched.

## Follow-ups

- The harness ack loop is now the B6 floor. Batching acks (or benchmarking the
  claim path without acks) is a separate issue; it is not a broker claim-path
  problem.
- A subscription with a large terminal history keeps the claim scan bounded by
  the partial pending index (measured above at 1M rows). No new index was
  needed.
