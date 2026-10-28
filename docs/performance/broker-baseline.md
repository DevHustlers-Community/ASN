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
  is passed, because it can delete non-benchmark rows.
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
