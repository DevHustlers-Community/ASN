---
date: 2026-11-05
type: perf
scope: broker
summary: Wake only the parked claims for subscriptions that received deliveries
breaking: false
adr: 0008
contracts: -
---

# Scope waiter wakeups to interested subscriptions

## Change

- `AsnEventBroker.Delivery.Waiters` now keys parked claims by subscription
  name (`{:subscription, name}`) and exposes `wake/1` instead of `wake_all/0`.
  A process is still parked for exactly one subscription at a time; `wake/1`
  deduplicates names and pids before sending `:wake`.
- `Delivery.claim/3` joins and leaves the registry for the subscription it is
  claiming.
- `Publishing.fan_out/2` returns the names of the subscriptions that received
  a delivery instead of a count, and `Publishing.publish/2` wakes only those
  subscriptions after the fan-out transaction commits. An empty fan-out wakes
  nobody.
- `services/event-broker/README.md`: record the scoped wakeup behavior.

The bookkeeping adds no database work: fan-out already selected the
subscription rows, so returning their names and resolving one `:pg` group per
affected subscription is local work only.

## Why

Issue #10: `wake_all/0` sent `:wake` to every parked claim on every publish
with at least one delivery. A consumer parked for an unrelated subscription
then ran a claim check it could never satisfy. The cost grows with parked
consumers times publish rate; correctness never depended on the wakeup because
the fallback sweep still bounds missed wakes.

## Verification

In-process wake benchmark on a dedicated `broker_b4` database: 30 claims parked
for unrelated subscriptions plus one parked for the target, then one publish
eligible for the target only, counted through the `[:asn_event_broker, :claim]`
telemetry events emitted in the first 400 ms (before the 1 s sweep):

| | Unrelated claim checks | Target wake latency |
|---|---|---|
| Before (`wake_all/0`) | 30 | 36 ms |
| After (`wake/1`) | 0 | 33 ms |

B4 (`scripts/dev/broker-load.py --scenario b4`, 300 rps, 10 s, 20 consumers),
two clean pairs, fresh database and broker per run:

| Run | Publish p50 / p95 / p99 (ms) | Claim visibility p50 / p95 / p99 (ms) |
|---|---|---|
| Before 1 | 60.31 / 89.27 / 126.3 | 4274 / 7121 / 7583 |
| After 1 | 55.86 / 78.55 / 89.38 | 3861 / 6960 / 8687 |
| Before 2 | 62.85 / 98.74 / 117.1 | 4704 / 7366 / 7923 |
| After 2 | 57.06 / 79.51 / 90.97 | 3519 / 6460 / 6939 |

B4 is noisy across runs; both clean pairs show lower publish latency and lower
p50/p95 claim visibility, and the second pair also lowers p99. The direct
in-process measurement is the wake-latency check.

- `mix format --check-formatted` — passed.
- `mix compile --warnings-as-errors` — passed.
- `mix test test/integration/delivery_test.exs` — 21 passed.
- `mix test` — 105 passed (3 properties, 102 tests).
- New tests:
  - `wake/1 messages only waiters registered for the named subscription`;
  - `publishing wakes only the subscriptions that received deliveries`.
- `python3 scripts/ci/check-links.py` — passed.
- `python3 scripts/ci/check-changelog.py --all` — passed.

## Follow-ups

- The fallback sweep remains the correctness bound; no behavior depends on a
  wakeup being delivered.
