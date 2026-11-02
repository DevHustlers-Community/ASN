---
date: 2026-11-02
type: docs
scope: broker
summary: Document and prove a dedicated broker_bench database for B6/B7 benchmarks
breaking: false
adr: 0008
contracts: -
---

# Document and prove a dedicated broker_bench database for B6/B7 benchmarks

## Change

- Extended the `## Running` part of
  [`docs/performance/broker-baseline.md`](../performance/broker-baseline.md)
  with a "Dedicated benchmark database (B6/B7)" subsection: manual
  `CREATE DATABASE broker_bench` (the init script only seeds on an empty
  volume), `mix ecto.migrate` with `BROKER_DATABASE_URL`, the broker start
  command for HTTP scenarios, and harness invocations with an explicit
  `--db-url`. It states that B7 must run without `--allow-shared-db` on this
  database, because the retention purge is global.
- Added a dated `2026-11-02` baseline section with the measured B6 10k and
  B7 10k results, explicit "not run" rows for the full-size targets and the
  reasons, and a decision note. No code, configuration, or contract changes.

## Why

The first baseline (2026-10-28) ran against the shared development database
with `--allow-shared-db`, and B7 could not run at all because the global
retention purge would delete non-benchmark rows. A dedicated benchmark
database removes both constraints and is required before deciding on
drain-rate and purge-scaling fixes.

## Verification

- `docker compose exec -T postgres psql -U postgres -c "CREATE DATABASE
  broker_bench OWNER asn_broker"` — created; `\dt` shows 6 tables including
  `schema_migrations`.
- `BROKER_DATABASE_URL=postgres://asn_broker:change_me@localhost:5432/broker_bench
  mix ecto.migrate` — applied all migrations.
- `python3 scripts/dev/broker-load.py --scenario b7 --rows 10000 --db-url
  postgres://...broker_bench --output /tmp/opencode/b7-bench-10k.json` —
  status `ok`, `allow_shared_db: false`, purge 2,615 ms; the JSON records
  `nonbench_expired_before` all 0, so the run was real, not skipped.
- Broker started on port 4004 against `broker_bench`, then
  `--scenario b6 --rows 10000` — status `ok`, 10,000 claimed and acked in
  145.69 s (68.64/s), 0 errors; broker stopped afterwards and port 4004
  confirmed free.
- Full-size B6 (1M rows) and B7 (2M delivered + 500k dead + 1M events) were
  **not run**: the measured drain rate puts a 1M-row backlog beyond the
  1800 s scenario budget, and B7 defaults seed millions of rows. Recorded as
  such in the baseline.
- `python3 scripts/ci/check-changelog.py --all` — passed.
- `python3 scripts/ci/check-links.py` — passed.

## Follow-ups

- Re-run B6 at 100k and 1M on `broker_bench` after the drain-rate work in
  issues #5/#6/#9.
- Run full-size B7 on `broker_bench` once retention purge scaling is decided.
