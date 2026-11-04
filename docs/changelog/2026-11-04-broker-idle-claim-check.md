---
date: 2026-11-04
type: perf
scope: broker
summary: Check claimability with one statement before taking the subscription lock
breaking: false
adr: 0008
contracts: -
---

# Check claimability with one statement before taking the subscription lock

## Change

- `services/event-broker/lib/asn_event_broker/delivery.ex`:
  - Added `@check_sql`: one query returns the subscription id and status, its
    leased count, and whether any delivery is claimable, using the same
    head-of-line and `next_attempt_at` predicates as the claim. It uses
    `statement_timestamp()` instead of `clock_timestamp()` so the predicate is
    a stable index bound and is not pinned to the start of the test sandbox
    transaction.
  - `claim_loop/3` joins the wakeup registry before each check and runs one
    check per iteration. A parked consumer with nothing claimable now runs one
    statement per `sweep_interval_ms` and takes no `FOR UPDATE` lock.
  - The claim transaction (`SELECT status ... FOR UPDATE`, in-flight count,
    `UPDATE ... SKIP LOCKED`) only starts when the check is positive; it
    re-validates the pause state under the lock and returns `:not_found` if the
    subscription disappeared while parked.
  - `lease_batch/4` and `in_flight_count/1` take the subscription id, so the
    subscription row is no longer fetched inside the claim transaction.
  - Wakes that arrived before a check are flushed, because the check already
    observed them; a publish that commits after the check leaves a `:wake` in
    the mailbox and wakes the consumer immediately.
  - Empty claims and in-flight-cap short-circuits still emit `[:claim]` with
    `count: 0`, so the empty-claim rate remains observable.
- [`services/event-broker/README.md`](../../services/event-broker/README.md#long-poll-claims):
  new "Long-poll claims" subsection.
- [`docs/performance/broker-baseline.md`](../performance/broker-baseline.md):
  B5 before/after measurement.

## Why

Issue #5. Every idle sweep ran a subscription fetch, a second fetch inside the
transaction, a `FOR UPDATE` lock, an in-flight count, and a claim `UPDATE`,
twice per loop iteration: 50 parked consumers produced 344 connection errors
out of 395 claim requests at `pool_size: 10` in the 2026-10-28 baseline.

The claim path only needs the expensive transaction when something is actually
claimable. The pre-check turns the idle case into one read per sweep, and
joining the wakeup registry before the check closes the wake race without a
second full claim attempt.

## Verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors` — passed.
- `mix test` — 90 passed (3 properties, 87 tests), including three new tests:
  - an idle claim runs exactly one statement and no `FOR UPDATE`;
  - a claim at the in-flight cap runs one check and no claim transaction;
  - pausing a subscription wakes a parked claim with `:paused`.
- `mix test` re-run with seeds 1, 2, and 3 — 90 passed each time.
- B5 on a dedicated `broker_b5`, 50 parked consumers, `wait_ms: 20000`, 30 s,
  `pool_size: 10`:
  - before (`upstream/main`): 135 requests, 46 errors (34%), 18,294 broker
    statements over 50.18 s (364.6/s), 6,004 `FOR UPDATE` lines;
  - after: 100 requests, 0 errors, 2,216 statements over 40.12 s (55.2/s),
    0 `FOR UPDATE` lines.
- Idle check plan on `broker_bench` (1M deliveries, 1,000 leased rows for
  another subscription): 0.295 ms warm, index scans on
  `deliveries_one_leased_per_aggregate` and
  `deliveries_subscription_id_next_attempt_at_index`.
- `bash tests/e2e/broker-relay.sh` — `E2E PASS: chat outbox -> relay ->
  broker -> claim -> ack -> metrics`.
- `python3 scripts/ci/check-changelog.py --all`,
  `python3 scripts/ci/check-links.py` — passed.

## Follow-ups

- B6 drain throughput (68.64/s at 10k pending rows) is not affected by this
  change; batched lease claims stay with issues #6 and #9.
- The check runs one extra `count(*)` over the subscription's leased rows. The
  partial unique index keeps that under 0.3 ms at the default cap, but it is
  another reason to keep `max_in_flight` bounded.
