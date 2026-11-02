---
date: 2026-11-02
type: fix
scope: broker
summary: Fix B6 seed order in broker-load harness and fail fast on a missing bench subscription
breaking: false
adr: 0008
contracts: -
---

# Fix B6 seed order in broker-load harness and fail fast on a missing bench subscription

## Change

- `scripts/dev/broker-load.py`: `run_scenario` no longer runs `cleanup_bench`
  before a seeding scenario starts. Cleanup still happens in `main()`'s
  `finally` block, after each seeding scenario finishes.
- `scripts/dev/broker-load.py`: `scenario_b6` raises a clear error when the
  bench subscription it just created over HTTP is not found in the database,
  instead of seeding deliveries against a null UUID.

## Why

The harness previously deleted all `bench-` rows at the start of every
seeding scenario. If two harness invocations overlapped (or anything else
created a live `bench-` subscription), the pre-scenario cleanup deleted a
subscription the drain seed still needed, and the `seed_pending` inserts
failed with `deliveries_subscription_id_fkey` violations. The fix removes
the cleanup call that ran before a seeding scenario, which was the trigger
reachable within a single invocation. The remaining cleanup still runs after
each scenario, in `main()`'s `finally` block, and is still a global
`DELETE ... WHERE name LIKE 'bench-%'`; two harness invocations must
therefore not run concurrently against the same database, because the
guarantee is per invocation, not global — one process's cleanup could still
delete the other's live `bench-` subscription mid-seed. The missing-subscription
check turns the old cryptic `''::uuid` cast failure
(`psql_scalar` returns an empty string when the SELECT matches nothing)
into an error that names the subscription, redacts the database URL, and
points at the most common cause: the broker HTTP edge and the harness not
using the same database.

This is a harness-only fix (GitHub issue #11). It does not change the
broker service, its delivery contract ([ADR 0008](../decisions/0008-broker-transport-and-delivery-contract.md)),
or any contract file.

## Verification

Environment: local Linux, PostgreSQL 18.6 via `compose.yaml` (`broker_db`),
broker with `pool_size: 10` and a single consumer, started with
`mix run --no-halt` against the same database.

- `python3 -m py_compile scripts/dev/broker-load.py` — OK.
- `python3 scripts/dev/broker-load.py --scenario b6 --rows 10000` — PASSED:
  `completed: true`, `errors: 0`, 10,000 seeded, 10,000 claimed and acked,
  `remaining_pending: 0`.
- `python3 scripts/dev/broker-load.py --scenario b6 --rows 100000` — did not
  complete: `completed: false`, `errors: 0`. Seeding of 100,000 rows succeeded
  in 6.94 s with zero `deliveries_subscription_id_fkey` errors, which is the
  behaviour this fix targets. The drain then processed 7,590 of 100,000 rows
  before the scenario's built-in window (`duration: 1800` in
  `SCENARIO_DEFAULTS["b6"]`) ended, leaving `remaining_pending: 92410`. No
  application error occurred.
- `psql` counts on `broker_db` before and after the runs — all `bench-` rows
  removed by the post-scenario cleanup; non-benchmark rows unchanged
  (3 service credentials, 1 subscription, 1 delivery, 1 event).
- `python3 scripts/ci/check-changelog.py --all` — OK.
- `python3 scripts/ci/check-links.py` — OK.

Run details:

| Run | completed | errors | Drain rate | Drain time |
|---|---|---|---|---|
| `--rows 10000` | `true` | 0 | 53.3 rows/s | 187.61 s |
| `--rows 100000` | `false` | 0 | 4.21 rows/s | 1801.25 s (window: 1800 s) |

No `mix test` was run: this change edits only the Python harness; no Elixir
files changed.

The incomplete 100k drain is a pre-existing throughput limitation of the
delivery path, not a regression: the drain path is untouched by this fix, the
10k run used the fixed harness to completion, and the throughput matches the
behaviour already reported for issue #9 (100k exceeding a bounded window in
the first baseline attempt) and the claim-cost analysis in issues #5/#6.

## Follow-ups

- 100k drain throughput remains owned by issues #5/#6/#9. A full-size baseline
  on a dedicated benchmark database is tracked by issue #12.
- The scenario JSON outputs were written to a local temp directory and are not
  committed to the repository.
