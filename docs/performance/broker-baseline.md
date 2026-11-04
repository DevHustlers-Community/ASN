# Event broker performance baseline

Benchmark harness: [`scripts/dev/broker-load.py`](../../scripts/dev/broker-load.py).
It is stdlib-only Python and talks to a running broker over HTTP plus the
broker database over `psql`.

## Safety

- Seeding and deletion only touch rows whose subscription name starts with
  `bench-`.
- The harness refuses to seed/delete against a non-local database host unless
  `--allow-nonlocal` is passed.
- The global retention purge (B7) refuses to run unless `--allow-shared-db`
  is passed or no non-benchmark expired rows exist, because it can delete
  non-benchmark rows. Never pass `--allow-shared-db` for B7 against the shared
  database; use a dedicated benchmark database instead (see
  [Running](#dedicated-benchmark-database-b67) below).
- Bench rows are cleaned up after each scenario finishes. A run terminated
  before cleanup completes (a hard kill such as SIGKILL or power loss, or a
  `cleanup_bench` failure) leaves `bench-` rows in place until a later
  seeding scenario's cleanup succeeds. Concurrent harness invocations
  against the same database are unsupported because the cleanup is global.
- Never point the harness at a production database.

## Scenarios

| ID | Scenario | Default | What it measures |
|---|---|---|---|
| B1 | Plan checks | — | `EXPLAIN (ANALYZE, BUFFERS)` for retention purge, metrics aggregate, in-flight count, and claim SQL; flags Seq Scans |
| B2 | Publish steady-state | 100 rps / 10 s, 1 subscription | publish p50/p95/p99, error rate |
| B3 | Fan-out burst | 200 rps / 10 s, 50 subscriptions | publish latency with wide fan-out |
| B4 | Claim + wake latency | 300 rps / 10 s, 20 consumers | publish-to-claim visibility |
| B5 | Idle parked cost | 50 consumers / 600 s, no traffic | idle DB statement rate |
| B6 | Backlog drain | 1,000,000 pending rows | drain rate over time, claim transaction duration |
| B7 | Retention purge | 2M delivered + 500k dead + 1M events | purge wall-clock, WAL/lock behaviour |
| B8 | Metrics scrape | table up to 5M rows | `GET /metrics` latency |
| B9 | Authorize cost | 500 rps / 10 s, 100 credentials | edge CPU/latency |

## Running

```bash
docker compose up -d postgres
cd services/event-broker && mix ecto.create && mix ecto.migrate
# For HTTP scenarios, start the broker:
BROKER_ADMIN_TOKEN=dev-admin-token mix run --no-halt

# In another shell:
python3 scripts/dev/broker-load.py --scenario b1 --output /tmp/b1.json
python3 scripts/dev/broker-load.py --scenario b2 --token dev-admin-token
python3 scripts/dev/broker-load.py --scenario all --token dev-admin-token --output /tmp/broker-all.json
```

B1 only needs PostgreSQL. HTTP scenarios need a running broker and a bearer
token with the required scopes.

### Dedicated benchmark database (B6/B7)

The retention purge (B7) is global: it deletes every expired delivered,
dead-lettered, and skipped delivery and every expired event with no retained
delivery, not just `bench-` rows. Therefore: **never run B7 with
`--allow-shared-db` against the shared development database (`broker_db`)** —
that flag explicitly accepts deleting non-benchmark rows there. Run B7 against
a dedicated `broker_bench` database instead, and without `--allow-shared-db`:
on a fresh `broker_bench` the harness's non-benchmark expired-row counts are
0, B7 runs unguarded, and its output records `allow_shared_db: false` as
evidence. On a populated shared database the same check is what makes B7
refuse to run at all.

B6 (backlog drain) benefits too: a broker that serves only `bench-`
subscriptions measures drain rates without distortion from real traffic.

The init script `infrastructure/postgres/init/01-create-databases.sh` only
creates databases on an empty volume, so create `broker_bench` once, manually:

```bash
docker compose exec -T postgres psql -U postgres \
  -c "CREATE DATABASE broker_bench OWNER asn_broker"
```

Migrate the dedicated database (the URL is selected by `BROKER_DATABASE_URL`
everywhere: dev repo config, `mix ecto.*`, the harness `--db-url` default, and
B7's purge subprocess):

```bash
cd services/event-broker && mix deps.get
BROKER_DATABASE_URL="postgres://asn_broker:change_me@localhost:5432/broker_bench" \
  mix ecto.migrate
```

For HTTP scenarios (B6), start the broker against the same database:

```bash
BROKER_DATABASE_URL="postgres://asn_broker:change_me@localhost:5432/broker_bench" \
  BROKER_ADMIN_TOKEN=dev-admin-token mix run --no-halt
```

Then run the harness with an explicit `--db-url` (`--db-url` falls back to
`BROKER_DATABASE_URL`; B7 needs no broker, B6 does):

```bash
python3 scripts/dev/broker-load.py --scenario b7 --rows 10000 \
  --db-url "postgres://asn_broker:change_me@localhost:5432/broker_bench" \
  --output /tmp/b7-bench.json
python3 scripts/dev/broker-load.py --scenario b6 --rows 10000 \
  --token dev-admin-token \
  --db-url "postgres://asn_broker:change_me@localhost:5432/broker_bench" \
  --output /tmp/b6-bench.json
```

Size the scenarios deliberately: B6 defaults to 1,000,000 pending rows and B7
defaults to 2M delivered + 500k dead + 1M events (harness
`SCENARIO_DEFAULTS`). Start at `--rows 10000` to prove the flow, then scale.

## Results template

Record a dated section per run:

```markdown
## YYYY-MM-DD — <git sha>

Environment: <CPU/RAM>, PostgreSQL <version>, broker pool_size <n>, Bandit <version>.

| Scenario | Metric | Result | Notes |
|---|---|---|---|
| B1 | claim_sql plan | Seq Scan / Index Scan | |
| B2 | publish p95 | ... ms | |
| B4 | publish-to-claim p95 | ... ms | |
| B8 | /metrics p95 at N rows | ... ms | |

Decision: <which fixes are justified by the data>.
```

## 2026-10-28 — local baseline (broker audit commit)

Environment: local Linux, PostgreSQL 18.6 (docker compose), broker `mix run
--no-halt`, `pool_size: 10`, Bandit 1.14.0. Shared dev database, so B2/B4/B5/B9
ran with `--allow-shared-db` and fanned out to one non-bench subscription.

| Scenario | Metric | Result | Notes |
|---|---|---|---|
| B1 | claim SQL plan | Seq Scan on `deliveries` | table had 1 row; re-run after seeding |
| B2 | publish 100 rps | p50 6.87 ms, p95 12.44 ms, p99 19.19 ms, 0 errors | 1,000 requests |
| B4 | publish 300 rps, 20 consumers | publish p95 157 ms; claim visibility p50 1.49 s, p95 3.96 s, p99 4.63 s | 661 claims/acks, 0 ack errors |
| B5 | 50 parked consumers, 30 s | 395 claim requests, 344 errors | DB pool exhausted (`DBConnection.ConnectionError`); confirms F4/pool risk |
| B8 | `/metrics` scrape | 100k rows: p50 23.9 ms, p95 26.3 ms; 20k: p95 8.4 ms; 2k: p95 3.9 ms | grows with `deliveries` size (F3) |
| B9 | 500 rps acks, 100 credentials | ack p50 7.06 ms, p95 13.64 ms, p99 24.46 ms; broker CPU 217% | high CPU consistent with per-request credential scan (F7) |
| B6 | backlog drain | not completed | harness seed bug: subscription removed before delivery insert; 100k run also exceeded 120 s |
| B7 | retention purge | not run | needs a dedicated benchmark database (global purge) |

### Decisions supported by this baseline

1. **F2 (retention worker) and F1 (`deliveries(event_id)` index):** B7 not run
   yet, but the missing worker is an ADR gap and the index is cheap; still
   recommended before any long-running deployment.
2. **F3 (metrics scrape):** confirmed growth (24 ms at 100k rows). Cache the
   gauge state before the table grows further.
3. **F4/pool:** B5 produced connection errors at 50 parked consumers with
   `pool_size: 10`; this is a real backpressure finding. Measure with a larger
   pool and/or trim idle sweep queries before raising the default.
4. **F7 (authorize):** 217% CPU at 500 rps with 100 credentials supports the
   index-lookup change.
5. **B6/B7:** fix the harness seed order and run against a dedicated
   benchmark database before deciding on F5 (batched lease) and purge tuning.

## 2026-11-02 — broker_bench (dedicated benchmark database)

Environment: local Linux, AMD Ryzen 5 4600G (12 threads), 13 GB RAM.
PostgreSQL 18.6 (docker compose, `postgres:18.6-alpine3.24`) with a dedicated
`broker_bench` database created manually (`CREATE DATABASE broker_bench OWNER
asn_broker` — the init script only seeds databases on an empty volume) and
migrated with `mix ecto.migrate`; 6 tables including `schema_migrations`
confirmed. Broker `mix run --no-halt` on port 4004 pointed at `broker_bench`
via `BROKER_DATABASE_URL`,
`pool_size: 10` (dev config), single consumer per claim (B6 harness default),
Bandit 1.14.0. B7 ran with no HTTP listener and no workers (harness purge
subprocess). Git sha `bdab65e`.

| Scenario | Metric | Result | Notes |
|---|---|---|---|
| B6 | backlog drain, 10,000 pending rows | 10,000 claimed and acked in 145.69 s (68.64/s), 1,000 batches of 100, seed 0.66 s, 0 errors, `remaining_pending: 0` | ran without `--allow-shared-db` (B6 never needs it); dedicated `broker_bench` |
| B6 | backlog drain at target size (1,000,000 pending rows) | not run | at the measured 68.64/s the default 1M-row backlog would exceed the 1800 s drain budget (a 100k-row attempt against `broker_db` earlier on 2026-11-02, before `broker_bench` existed, drained 7,590 of 100,000 rows at 4.21/s before hitting the 1800 s budget); waiting on drain-rate fixes before re-running — tracked in issues #5, #6, #9 |
| B7 | retention purge, 10,000 base rows (20,000 delivered + 5,000 dead + 10,000 extra events) | purged 20,000 delivered, 5,000 terminal, and 35,000 events in 2,615 ms; seed 1.66 s, run wall-clock 3.51 s | ran **without** `--allow-shared-db`; JSON records `allow_shared_db: false` and `nonbench_expired_before` all 0, proving the guard was not bypassed |
| B7 | retention purge at target size (2M delivered + 500k dead + 1M events) | not run | harness defaults seed millions of rows; first prove the flow at reduced size, scale after purge tuning is decided — tracked in issues #5, #9 |

### Decisions supported by this run

1. **Dedicated database path works:** B7 ran end to end with zero
   non-benchmark rows at risk because `broker_bench` contained no
   non-`bench-` data; the `--allow-shared-db` override is no longer needed
   for any scenario. This is the documented path for future B6/B7 runs.
2. **Drain throughput is the open problem:** 68.64/s at 10k rows means a
   default-size B6 backlog takes hours. Batched lease / claim-path work in
   issues #5, #6, and #9 should target this number; re-run B6 at 100k and 1M
   on `broker_bench` after those land.
3. **Purge is viable but untested at scale:** the 10k run deleted 60,000 rows
   (25,000 deliveries + 35,000 events) in 2,615 ms (~22,900 rows/s);
   full-size B7 (2M delivered + 500k dead + 1M events, ~3.5M rows seeded) is
   the next measurement once the retention worker decisions (F2) are settled.

## 2026-11-04 — idle sweep cost (issue #5)

Environment: same host, PostgreSQL 18.6, dedicated `broker_b5` database
(`CREATE DATABASE broker_b5 OWNER asn_broker`, then `mix ecto.migrate`), broker
`mix run --no-halt` on port 4004, `pool_size: 10` (dev config), Bandit 1.14.0.
B5: 50 parked consumers, `wait_ms: 20000`, 30 s of load. Statement counts come
from the broker's own `QUERY OK` log lines (pg_stat_statements is not enabled
on this cluster); the harness reported HTTP-level requests and errors.

| Run | Claim requests | Errors | Broker statements | Statements/s | `FOR UPDATE` lines |
|---|---|---|---|---|---|
| before (`upstream/main`) | 135 | 46 (34%) | 18,294 over 50.18 s | 364.6 | 6,004 |
| after | 100 | 0 | 2,216 over 40.12 s | 55.2 | 0 |

The run durations differ because errored requests returned immediately and
retried, so the rate is the comparable figure. Per parked consumer the sweep
cost fell from ~7.3 statements/s to ~1.1 statements/s, one check per
`sweep_interval_ms`. The 8 `UPDATE deliveries` lines in the after log are the
lease reaper's every-5-second pass over an empty lease set, not claims.

Idle check plan on `broker_bench` (1,000,000 deliveries plus 1,000 leased
rows for another subscription): the leased count uses a bitmap index scan on
`deliveries_one_leased_per_aggregate`, the claimable probe uses
`deliveries_subscription_id_next_attempt_at_index`, and the whole check runs in
0.295 ms warm. The outer `subscriptions` lookup was a sequential scan only
because the bench table has two rows.

### Decision

`pool_size: 10` is enough for 50 parked consumers: 0 connection errors and no
lock acquisition while idle, so no default change is needed. The remaining B6
drain throughput (68.64/s) is a different problem — claimed batches, not idle
sweeps — and stays with issues #6 and #9.

