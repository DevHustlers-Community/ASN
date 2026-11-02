---
date: 2026-11-02
type: feat
scope: broker
summary: Run dependency-aware retention purge on a scheduled broker worker
breaking: false
adr: 0008
contracts: -
---

# Run dependency-aware retention purge on a scheduled broker worker

## Change

- Added `services/event-broker/lib/asn_event_broker/workers/retention_worker.ex`:
  `AsnEventBroker.Workers.RetentionWorker` is a GenServer scheduler that calls
  `Retention.purge/1` every `retention_interval_ms` and logs a one-line summary
  when rows are deleted. All purge logic stays in `Retention.purge/1`; the
  worker runs the purge inline (the next tick is scheduled after the previous
  purge returns, so runs cannot overlap) and lets database errors crash the
  process for the supervisor to restart.
- Registered the worker next to `Workers.LeaseReaper` in
  `maybe_add_workers/1` in
  `services/event-broker/lib/asn_event_broker/application.ex`. It is therefore
  covered by the existing `:start_workers` gate and disabled under the test
  sandbox.
- Added `retention_interval_ms: 3_600_000` (hourly) to
  `config :asn_event_broker, :retention` in
  `services/event-broker/config/config.exs` and extended the config comment.
- Documented the scheduled workers and the retention config in the service
  [`README`](../../services/event-broker/README.md) and added a `## Workers`
  section to [`CODE_MAP.md`](../../services/event-broker/CODE_MAP.md).
- Added `test/integration/retention_worker_test.exs` covering: the worker is
  disabled under the sandbox, it purges expired deliveries and their events on
  its interval, and it exits with a non-`:normal` reason when the purge raises.

## Why

ADR 0008 §8 defines the retention policy, but `Retention.purge/1` was only ever
invoked from tests; nothing purged `broker_db` in a running broker. Retention
belongs on the event-log floor if replay and dead-letter windows are to hold up
in practice, so it must run as a scheduled worker like the lease reaper (issue
#3). Keeping the logic in `Retention.purge/1` preserves the existing direct-call
test contract; the GenServer adds only scheduling.

## Verification

- `mix format --check-formatted` — passed.
- `mix compile --warnings-as-errors` — passed, no warnings.
- `mix test` — 87 passed (84 tests, 3 properties), including the three new
  `RetentionWorkerTest` tests, against real PostgreSQL (`docker compose ps`
  shows `asn-postgres-1` healthy).
- Smoke run: started the broker against `broker_dev` (`broker_db`) with
  `retention_interval_ms` shortened to 2000 ms via `mix run --no-start` eval
  before `Application.ensure_all_started/1`; inserted one stale delivered
  delivery and its overdue event directly into `broker_db`; the first
  scheduled tick deleted both (`retention purge: 1 delivered, 0 terminal, 1
  events deleted`), `asn_event_broker_retention_purged_total` appeared on
  `/metrics`, and the broker was stopped afterwards with port 4004 confirmed
  free.
- `python3 scripts/ci/check-changelog.py --all` — passed.
- `python3 scripts/ci/check-links.py` — passed.

## Follow-ups

- Measure purge latency on multi-million-row tables once B6/B7 full-size
  baselines land, then decide (ADR) whether the purge needs a larger
  `batch_size` per run or a shorter interval.
