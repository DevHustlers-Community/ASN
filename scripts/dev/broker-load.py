#!/usr/bin/env python3
"""Event broker benchmark harness (scenarios B1-B9).

Benchmark-first: this script never changes broker production code. It seeds
rows only under the ``bench-`` prefix, uses ``psql`` for SQL and ``urllib`` for
HTTP, and refuses to touch a non-local database unless ``--allow-nonlocal`` is
given.

The scenario names and defaults come from the broker baseline investigation.
Run ``--help`` for flags. Results are written as JSON to ``--output`` and a
human-readable Markdown summary is printed to stdout.

Examples:

    python3 scripts/dev/broker-load.py --scenario b1 --output /tmp/broker-b1.json
    python3 scripts/dev/broker-load.py --scenario b2 --rps 100 --duration 10
    python3 scripts/dev/broker-load.py --scenario all --output /tmp/broker-all.json

Safety notes live in ``docs/performance/broker-baseline.md``.
"""

from __future__ import annotations

import argparse
import bisect
import concurrent.futures
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BROKER_DIR = REPO_ROOT / "services" / "event-broker"
BENCH_PREFIX = "bench-"
DEFAULT_BASE_URL = "http://localhost:4004"
DEFAULT_DB_URL = os.environ.get(
    "BROKER_DATABASE_URL",
    "postgres://asn_broker:change_me@localhost:5432/broker_db",
)
LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1", None}

SCENARIOS = ["b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8", "b9"]
SEEDING_SCENARIOS = {"b2", "b3", "b4", "b5", "b6", "b7", "b8", "b9"}

# Per-scenario defaults. Explicit CLI flags always win.
SCENARIO_DEFAULTS = {
    "b2": {"rps": 100, "duration": 10, "consumers": 1, "rows": 0, "max": 10, "wait_ms": 0},
    "b3": {"rps": 200, "duration": 10, "consumers": 1, "rows": 0, "max": 10, "wait_ms": 0},
    "b4": {"rps": 300, "duration": 10, "consumers": 20, "rows": 0, "max": 10, "wait_ms": 5000},
    "b5": {"rps": 0, "duration": 600, "consumers": 50, "rows": 0, "max": 10, "wait_ms": 20000},
    "b6": {"rps": 0, "duration": 1800, "consumers": 1, "rows": 1_000_000, "max": 100, "wait_ms": 0},
    "b7": {"rps": 0, "duration": 0, "consumers": 1, "rows": 1_000_000, "max": 0, "wait_ms": 0},
    "b8": {"rps": 0, "duration": 0, "consumers": 1, "rows": 5_000_000, "max": 0, "wait_ms": 0},
    "b9": {"rps": 500, "duration": 10, "consumers": 1, "rows": 10_000, "max": 0, "wait_ms": 0},
}


# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso_now() -> str:
    return utc_now().isoformat(timespec="microseconds").replace("+00:00", "Z")


def parse_iso(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def redact_url(url: str) -> str:
    """Render a database URL without credentials for output files."""
    parsed = urllib.parse.urlparse(url)
    host = parsed.hostname or "local"
    port = f":{parsed.port}" if parsed.port else ""
    return f"{parsed.scheme}://{host}{port}{parsed.path}"


def db_host(url: str) -> str | None:
    return urllib.parse.urlparse(url).hostname


def bench_uuid(tag: str, kind: str, index: int) -> str:
    """Stable UUID used by both the seeder and the HTTP client."""
    digest = hashlib.md5(f"{tag}-{kind}-{index}".encode()).hexdigest()
    return str(uuid.UUID(hex=digest))


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def percentile(sorted_values: list[float], pct: float) -> float:
    if not sorted_values:
        return 0.0
    index = int(round((pct / 100.0) * (len(sorted_values) - 1)))
    return sorted_values[min(max(index, 0), len(sorted_values) - 1)]


def summarize(values: list[float]) -> dict:
    if not values:
        return {"count": 0}
    ordered = sorted(values)
    return {
        "count": len(ordered),
        "min": round(ordered[0], 2),
        "p50": round(percentile(ordered, 50), 2),
        "p95": round(percentile(ordered, 95), 2),
        "p99": round(percentile(ordered, 99), 2),
        "max": round(ordered[-1], 2),
        "mean": round(statistics.fmean(ordered), 2),
    }


def rate_buckets(samples: list[tuple[float, int]], bucket_seconds: float = 5.0) -> list[dict]:
    """Turn cumulative (elapsed, count) samples into per-bucket rates."""
    if not samples:
        return []
    ordered = sorted(samples)
    times = [elapsed for elapsed, _ in ordered]
    counts = [count for _, count in ordered]

    def count_at(moment: float) -> int:
        index = bisect.bisect_right(times, moment) - 1
        return counts[index] if index >= 0 else 0

    buckets: list[dict] = []
    start = 0.0
    total_time = times[-1]
    while start < total_time:
        end = min(start + bucket_seconds, total_time)
        count = count_at(end) - count_at(start)
        buckets.append(
            {
                "start_s": round(start, 2),
                "end_s": round(end, 2),
                "count": count,
                "rate_per_s": round(count / (end - start), 2) if end > start else 0,
            }
        )
        start = end
    return buckets


# ---------------------------------------------------------------------------
# PostgreSQL helpers (psql subprocess only; no driver dependency)
# ---------------------------------------------------------------------------


def psql(db_url: str, sql: str, timeout: float | None = None) -> dict:
    cmd = [
        "psql",
        "-X",
        "-q",
        "-A",
        "-t",
        "-v",
        "ON_ERROR_STOP=1",
        "-d",
        db_url,
        "-f",
        "-",
    ]
    try:
        proc = subprocess.run(
            cmd,
            input=sql,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError:
        return {"returncode": 127, "stdout": "", "stderr": "psql not found on PATH"}
    except subprocess.TimeoutExpired as exc:
        return {
            "returncode": 124,
            "stdout": (exc.stdout or ""),
            "stderr": f"psql timed out after {timeout}s",
        }
    return {
        "returncode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
    }


def require_psql(db_url: str) -> None:
    result = psql(db_url, "SELECT 1;\n", timeout=10)
    if result["returncode"] != 0:
        raise RuntimeError(f"psql is not usable: {result['stderr'].strip()}")


def psql_scalar(db_url: str, sql: str, timeout: float | None = None) -> str:
    result = psql(db_url, sql, timeout=timeout)
    if result["returncode"] != 0:
        raise RuntimeError(f"SQL failed: {result['stderr'].strip()}")
    lines = [line for line in result["stdout"].splitlines() if line.strip()]
    return lines[-1].strip() if lines else ""


def psql_int(db_url: str, sql: str, timeout: float | None = None) -> int:
    value = psql_scalar(db_url, sql, timeout=timeout)
    return int(value) if value else 0


def table_counts(db_url: str) -> dict:
    sql = """
SELECT 'deliveries', count(*) FROM deliveries
UNION ALL SELECT 'events', count(*) FROM events
UNION ALL SELECT 'subscriptions', count(*) FROM subscriptions
UNION ALL SELECT 'service_credentials', count(*) FROM service_credentials
ORDER BY 1;
"""
    result = psql(db_url, sql)
    counts: dict[str, int] = {}
    if result["returncode"] != 0:
        return counts
    for line in result["stdout"].splitlines():
        if "|" in line:
            name, value = line.split("|", 1)
            counts[name] = int(value)
    return counts


def cleanup_bench(db_url: str) -> None:
    """Delete only rows created by this harness (``bench-`` prefix).

    The order is dependency-aware: audit rows, credentials, deliveries, events,
    then subscriptions. Deliveries attached to bench events are removed even
    when a non-bench subscription received one (only possible with
    ``--allow-shared-db``), because the event foreign key is RESTRICT.
    """
    sql = f"""
DELETE FROM audit_log
WHERE actor_credential_id IN (
  SELECT credential_id FROM service_credentials WHERE service_name LIKE '{BENCH_PREFIX}%'
)
OR target IN (
  SELECT 'credential:' || credential_id::text
  FROM service_credentials WHERE service_name LIKE '{BENCH_PREFIX}%'
)
OR target LIKE 'subscription:{BENCH_PREFIX}%';

DELETE FROM service_credentials WHERE service_name LIKE '{BENCH_PREFIX}%';

DELETE FROM deliveries
WHERE subscription_id IN (
  SELECT id FROM subscriptions WHERE name LIKE '{BENCH_PREFIX}%'
)
OR event_id IN (
  SELECT event_id FROM events WHERE publisher LIKE '{BENCH_PREFIX}%'
);

DELETE FROM events
WHERE publisher LIKE '{BENCH_PREFIX}%'
  AND NOT EXISTS (SELECT 1 FROM deliveries d WHERE d.event_id = events.event_id);

DELETE FROM subscriptions WHERE name LIKE '{BENCH_PREFIX}%';
"""
    result = psql(db_url, sql)
    if result["returncode"] != 0:
        raise RuntimeError(f"benchmark cleanup failed: {result['stderr'].strip()}")


def nonbench_active_subscriptions(db_url: str) -> int:
    return psql_int(
        db_url,
        f"SELECT count(*) FROM subscriptions WHERE status = 'active' AND name NOT LIKE '{BENCH_PREFIX}%';\n",
    )


def nonbench_expired_counts(db_url: str) -> dict:
    sql = f"""
SELECT
  (SELECT count(*) FROM deliveries
   WHERE state = 'delivered'
     AND delivered_at <= now() - interval '24 hours'
     AND subscription_id NOT IN (SELECT id FROM subscriptions WHERE name LIKE '{BENCH_PREFIX}%')),
  (SELECT count(*) FROM deliveries
   WHERE ((state = 'dead' AND dead_lettered_at <= now() - interval '30 days')
       OR (state = 'skipped' AND skipped_at <= now() - interval '30 days'))
     AND subscription_id NOT IN (SELECT id FROM subscriptions WHERE name LIKE '{BENCH_PREFIX}%')),
  (SELECT count(*) FROM events
   WHERE received_at <= now() - interval '7 days'
     AND publisher NOT LIKE '{BENCH_PREFIX}%');
"""
    result = psql(db_url, sql)
    if result["returncode"] != 0:
        raise RuntimeError(f"expired-row check failed: {result['stderr'].strip()}")
    row = [line for line in result["stdout"].splitlines() if line.strip()][-1]
    delivered, terminal, events = (int(part) for part in row.split("|"))
    return {"delivered": delivered, "terminal": terminal, "events": events}


# ---------------------------------------------------------------------------
# HTTP helpers (urllib only)
# ---------------------------------------------------------------------------


def http_call(
    method: str,
    url: str,
    body: dict | None = None,
    token: str | None = None,
    timeout: float = 30.0,
) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    if body is not None:
        request.add_header("content-type", "application/json")
    if token:
        request.add_header("Authorization", f"Bearer {token}")

    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
            return {
                "status": response.status,
                "body": raw.decode("utf-8", errors="replace"),
                "latency_ms": (time.perf_counter() - started) * 1000.0,
                "error": None,
            }
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        return {
            "status": exc.code,
            "body": raw.decode("utf-8", errors="replace"),
            "latency_ms": (time.perf_counter() - started) * 1000.0,
            "error": None,
        }
    except Exception as exc:  # noqa: BLE001 - benchmark records the failure
        return {
            "status": None,
            "body": "",
            "latency_ms": (time.perf_counter() - started) * 1000.0,
            "error": str(exc),
        }


def response_json(response: dict) -> dict | None:
    try:
        return json.loads(response["body"])
    except (TypeError, ValueError):
        return None


def wait_ready(base_url: str, timeout: float = 15.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        response = http_call("GET", f"{base_url}/readyz", timeout=2.0)
        if response["status"] == 200:
            return True
        time.sleep(0.5)
    return False


def skip(reason: str) -> dict:
    print(f"    SKIP: {reason}", file=sys.stderr)
    return {"status": "skipped", "note": reason}


def create_subscription(
    base_url: str, admin_token: str, name: str, event_types: list[str] | None
) -> None:
    body = {"name": name, "consumer": "bench-load"}
    if event_types is not None:
        body["event_types"] = event_types
    response = http_call("POST", f"{base_url}/v1/subscriptions", body, admin_token)
    if response["status"] not in (201, 409):
        raise RuntimeError(
            f"subscription {name} failed: HTTP {response['status']} {response['body'][:300]}"
        )


def issue_credential(base_url: str, admin_token: str, service_name: str) -> str:
    response = http_call(
        "POST",
        f"{base_url}/v1/credentials",
        {"service_name": service_name, "scopes": ["publish", "consume"]},
        admin_token,
    )
    if response["status"] != 201:
        raise RuntimeError(
            f"credential issuance failed: HTTP {response['status']} {response['body'][:300]}"
        )
    payload = response_json(response) or {}
    token = payload.get("token")
    if not token:
        raise RuntimeError("credential issuance returned no token")
    return token


# ---------------------------------------------------------------------------
# Load generation
# ---------------------------------------------------------------------------


def run_load(duration: float, rps: float, fn, max_workers: int = 64) -> tuple[list[dict], float, int]:
    """Drive ``fn(i)`` at roughly ``rps`` for ``duration`` seconds."""
    total = max(1, int(round(duration * rps)))
    results: list[dict] = []
    lock = threading.Lock()

    def wrapped(index: int) -> None:
        result = fn(index)
        with lock:
            results.append(result)

    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = []
        for index in range(total):
            target = started + index / rps
            delay = target - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            futures.append(pool.submit(wrapped, index))
        for future in futures:
            future.result()
    elapsed = time.monotonic() - started
    return results, elapsed, total


def load_summary(results: list[dict], elapsed: float, total: int, expected: set[int]) -> dict:
    latencies = [result["latency_ms"] for result in results]
    statuses: dict[str, int] = {}
    errors = 0
    for result in results:
        key = str(result["status"]) if result["status"] is not None else "error"
        statuses[key] = statuses.get(key, 0) + 1
        if result["status"] not in expected:
            errors += 1
    return {
        "requests": total,
        "completed": len(results),
        "elapsed_s": round(elapsed, 2),
        "rps_actual": round(len(results) / elapsed, 2) if elapsed > 0 else 0,
        "error_rate": round(errors / len(results), 4) if results else 1.0,
        "status_counts": statuses,
        "latency_ms": summarize(latencies),
    }


def publish_envelope(index: int, event_type: str = "bench.load") -> dict:
    return {
        "event_id": str(uuid.uuid4()),
        "type": event_type,
        "schema_version": 1,
        "occurred_at": iso_now(),
        "payload": {"i": index},
    }


def claim(
    base_url: str,
    token: str,
    subscription: str,
    max_deliveries: int,
    wait_ms: int,
) -> dict:
    timeout = max(10.0, wait_ms / 1000.0 + 10.0)
    return http_call(
        "POST",
        f"{base_url}/v1/subscriptions/{urllib.parse.quote(subscription)}/claims",
        {"max": max_deliveries, "wait_ms": wait_ms},
        token,
        timeout=timeout,
    )


def ack(base_url: str, token: str, delivery_id: str, lease_token: str) -> dict:
    return http_call(
        "POST",
        f"{base_url}/v1/deliveries/{delivery_id}/ack",
        {"lease_token": lease_token},
        token,
        timeout=15.0,
    )


# ---------------------------------------------------------------------------
# Seeding helpers
# ---------------------------------------------------------------------------


def chunk_ranges(total: int, chunk_size: int = 100_000):
    for start in range(1, total + 1, chunk_size):
        yield start, min(total, start + chunk_size - 1)


def seed_pending(db_url: str, subscription_id: str, total: int, tag: str) -> None:
    statements = []
    for start, end in chunk_ranges(total):
        statements.append(
            f"""
INSERT INTO events (event_id, type, schema_version, occurred_at, payload, content_hash, publisher, received_at)
SELECT md5('{tag}-event-' || g)::uuid, 'bench.seeded', 1, now(), '{{}}'::jsonb,
       repeat('b', 64), 'bench-load', now()
FROM generate_series({start}, {end}) AS g;

INSERT INTO deliveries (id, subscription_id, event_id, state, attempts, max_attempts, created_at, updated_at)
SELECT md5('{tag}-delivery-' || g)::uuid, '{subscription_id}'::uuid,
       md5('{tag}-event-' || g)::uuid, 'pending', 0, 5, now(), now()
FROM generate_series({start}, {end}) AS g;
"""
        )
    result = psql(db_url, "\n".join(statements), timeout=None)
    if result["returncode"] != 0:
        raise RuntimeError(f"pending seed failed: {result['stderr'].strip()}")


def seed_leased(
    db_url: str,
    subscription_id: str,
    total: int,
    tag: str,
    lease_token: str,
    lease_hash: str,
) -> None:
    statements = []
    for start, end in chunk_ranges(total):
        statements.append(
            f"""
INSERT INTO events (event_id, type, schema_version, occurred_at, payload, content_hash, publisher, received_at)
SELECT md5('{tag}-event-' || g)::uuid, 'bench.seeded', 1, now(), '{{}}'::jsonb,
       repeat('b', 64), 'bench-load', now()
FROM generate_series({start}, {end}) AS g;

INSERT INTO deliveries (
  id, subscription_id, event_id, state, attempts, max_attempts,
  lease_token_hash, lease_expires_at, created_at, updated_at
)
SELECT md5('{tag}-delivery-' || g)::uuid, '{subscription_id}'::uuid,
       md5('{tag}-event-' || g)::uuid, 'leased', 1, 5,
       '{lease_hash}', now() + interval '2 hours', now(), now()
FROM generate_series({start}, {end}) AS g;
"""
        )
    result = psql(db_url, "\n".join(statements), timeout=None)
    if result["returncode"] != 0:
        raise RuntimeError(f"leased seed failed: {result['stderr'].strip()}")


def seed_retention(db_url: str, subscription_id: str, rows: int, tag: str) -> dict:
    delivered = rows * 2
    dead = max(1, rows // 2)
    extra = rows
    statements = []

    for start, end in chunk_ranges(delivered):
        statements.append(
            f"""
INSERT INTO events (event_id, type, schema_version, occurred_at, payload, content_hash, publisher, received_at)
SELECT md5('{tag}-d-event-' || g)::uuid, 'bench.seeded', 1,
       now() - interval '8 days', '{{}}'::jsonb, repeat('b', 64), 'bench-load',
       now() - interval '8 days'
FROM generate_series({start}, {end}) AS g;

INSERT INTO deliveries (
  id, subscription_id, event_id, state, attempts, max_attempts,
  lease_token_hash, delivered_at, created_at, updated_at
)
SELECT md5('{tag}-d-delivery-' || g)::uuid, '{subscription_id}'::uuid,
       md5('{tag}-d-event-' || g)::uuid, 'delivered', 1, 5,
       repeat('c', 64), now() - interval '25 hours',
       now() - interval '8 days', now() - interval '8 days'
FROM generate_series({start}, {end}) AS g;
"""
        )

    for start, end in chunk_ranges(dead):
        statements.append(
            f"""
INSERT INTO events (event_id, type, schema_version, occurred_at, payload, content_hash, publisher, received_at)
SELECT md5('{tag}-x-event-' || g)::uuid, 'bench.seeded', 1,
       now() - interval '8 days', '{{}}'::jsonb, repeat('b', 64), 'bench-load',
       now() - interval '8 days'
FROM generate_series({start}, {end}) AS g;

INSERT INTO deliveries (
  id, subscription_id, event_id, state, attempts, max_attempts,
  dead_lettered_at, created_at, updated_at
)
SELECT md5('{tag}-x-delivery-' || g)::uuid, '{subscription_id}'::uuid,
       md5('{tag}-x-event-' || g)::uuid, 'dead', 5, 5,
       now() - interval '31 days', now() - interval '8 days', now() - interval '8 days'
FROM generate_series({start}, {end}) AS g;
"""
        )

    for start, end in chunk_ranges(extra):
        statements.append(
            f"""
INSERT INTO events (event_id, type, schema_version, occurred_at, payload, content_hash, publisher, received_at)
SELECT md5('{tag}-e-event-' || g)::uuid, 'bench.seeded', 1,
       now() - interval '8 days', '{{}}'::jsonb, repeat('b', 64), 'bench-load',
       now() - interval '8 days'
FROM generate_series({start}, {end}) AS g;
"""
        )

    result = psql(db_url, "\n".join(statements), timeout=None)
    if result["returncode"] != 0:
        raise RuntimeError(f"retention seed failed: {result['stderr'].strip()}")

    return {
        "delivered": delivered,
        "dead": dead,
        "extra_events": extra,
        "total_events": delivered + dead + extra,
    }


def seed_credentials(db_url: str, total: int, tag: str) -> list[dict]:
    rows = []
    credentials = []
    for index in range(total):
        service_name = f"{tag}-auth-{index:03d}"
        token = f"{tag}-token-{index:03d}"
        credential_id = bench_uuid(tag, "credential", index)
        credentials.append({"service_name": service_name, "token": token})
        rows.append(
            f"('{credential_id}'::uuid, '{service_name}', '{sha256_hex(token)}', "
            f"ARRAY['consume'], now(), now())"
        )
    sql = f"""
INSERT INTO service_credentials (
  credential_id, service_name, token_hash, scopes, created_at, updated_at
) VALUES
{",".join(rows)}
ON CONFLICT (credential_id) DO NOTHING;
"""
    result = psql(db_url, sql, timeout=None)
    if result["returncode"] != 0:
        raise RuntimeError(f"credential seed failed: {result['stderr'].strip()}")
    return credentials


# ---------------------------------------------------------------------------
# Scenario B1: query-plan checks
# ---------------------------------------------------------------------------


def insert_bench_subscription(db_url: str, name: str, subscription_id: str) -> None:
    result = psql(
        db_url,
        f"""
INSERT INTO subscriptions (id, name, consumer, status, max_attempts, created_at, updated_at)
VALUES ('{subscription_id}'::uuid, '{name}', 'bench-load', 'active', 5, now(), now());
""",
    )
    if result["returncode"] != 0:
        raise RuntimeError(f"subscription seed failed: {result['stderr'].strip()}")


def explain_check(db_url: str, name: str, sql: str, transactional: bool = False) -> dict:
    statement = sql.strip().rstrip(";")
    if transactional:
        script = f"BEGIN;\nEXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)\n{statement};\nROLLBACK;\n"
    else:
        script = f"EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)\n{statement};\n"
    result = psql(db_url, script, timeout=300)
    plan = result["stdout"].strip()
    execution_ms = None
    match = re.search(r"Execution Time:\s*([0-9.]+)\s*ms", plan)
    if match:
        execution_ms = float(match.group(1))
    return {
        "status": "ok" if result["returncode"] == 0 else "error",
        "sql": statement,
        "plan": plan,
        "seq_scan": "Seq Scan" in plan,
        "index_scan": "Index Scan" in plan or "Index Only Scan" in plan,
        "bitmap_scan": "Bitmap" in plan,
        "execution_ms": execution_ms,
        "error": result["stderr"].strip() if result["returncode"] != 0 else None,
    }


def scenario_b1(args, db_url: str) -> dict:
    random_subscription = str(uuid.uuid4())
    purge_delivered = """
DELETE FROM deliveries
WHERE id IN (
  SELECT id FROM deliveries
  WHERE state = 'delivered'
    AND delivered_at <= now() - interval '24 hours'
  LIMIT 1000
)
"""
    purge_terminal = """
DELETE FROM deliveries
WHERE id IN (
  SELECT id FROM deliveries
  WHERE (state = 'dead' AND dead_lettered_at <= now() - interval '30 days')
     OR (state = 'skipped' AND skipped_at <= now() - interval '30 days')
  LIMIT 1000
)
"""
    purge_events = """
DELETE FROM events
WHERE event_id IN (
  SELECT e.event_id
  FROM events e
  WHERE e.received_at <= now() - interval '7 days'
    AND NOT EXISTS (
      SELECT 1 FROM deliveries d
      WHERE d.event_id = e.event_id
        AND (
          d.state IN ('pending', 'leased')
          OR (d.state = 'delivered' AND d.delivered_at > now() - interval '24 hours')
          OR (d.state = 'dead' AND d.dead_lettered_at > now() - interval '30 days')
          OR (d.state = 'skipped' AND d.skipped_at > now() - interval '30 days')
        )
    )
  LIMIT 1000
)
"""
    metrics_aggregate = """
SELECT
  count(d0.id) FILTER (WHERE d0.state = 'pending'),
  count(d0.id) FILTER (WHERE d0.state = 'leased'),
  count(d0.id) FILTER (WHERE d0.state = 'dead'),
  min(d0.created_at) FILTER (WHERE d0.state = 'pending')
FROM deliveries AS d0
"""
    in_flight = f"""
SELECT count(*)
FROM deliveries AS d0
WHERE d0.subscription_id = '{random_subscription}'::uuid
  AND d0.state = 'leased'
"""
    claim_sql = """
UPDATE deliveries d
SET state = 'leased',
    attempts = d.attempts + 1,
    lease_token_hash = repeat('a', 64),
    lease_expires_at = clock_timestamp() + (30 * interval '1 second'),
    updated_at = now()
WHERE d.id = (
  SELECT c.id
  FROM deliveries c
  WHERE c.subscription_id = 'SUB_ID'::uuid
    AND c.state = 'pending'
    AND (c.next_attempt_at IS NULL OR c.next_attempt_at <= clock_timestamp())
    AND (
      c.aggregate_type IS NULL
      OR NOT EXISTS (
        SELECT 1
        FROM deliveries e
        WHERE e.subscription_id = c.subscription_id
          AND e.aggregate_type = c.aggregate_type
          AND e.aggregate_id = c.aggregate_id
          AND e.state IN ('pending', 'leased', 'dead')
          AND e.id <> c.id
          AND e.aggregate_version < c.aggregate_version
      )
    )
  ORDER BY c.aggregate_version NULLS LAST
  LIMIT 1
  FOR UPDATE SKIP LOCKED
)
RETURNING d.id, d.event_id, d.aggregate_type, d.aggregate_id,
          d.aggregate_version, d.attempts, d.lease_expires_at
""".replace("SUB_ID", random_subscription)

    checks = {
        "retention_purge_delivered": explain_check(
            db_url, "retention_purge_delivered", purge_delivered, transactional=True
        ),
        "retention_purge_terminal": explain_check(
            db_url, "retention_purge_terminal", purge_terminal, transactional=True
        ),
        "retention_purge_events": explain_check(
            db_url, "retention_purge_events", purge_events, transactional=True
        ),
        "metrics_filter_aggregate": explain_check(
            db_url, "metrics_filter_aggregate", metrics_aggregate
        ),
        "in_flight_count": explain_check(db_url, "in_flight_count", in_flight),
        "claim_sql": explain_check(db_url, "claim_sql", claim_sql, transactional=True),
    }

    return {
        "status": "ok",
        "table_counts": table_counts(db_url),
        "checks": checks,
    }


# ---------------------------------------------------------------------------
# Scenarios B2/B3/B4: HTTP publish and claim load
# ---------------------------------------------------------------------------


def scenario_publish(args, base_url: str, admin_token: str, subscriptions: int, event_type: str) -> dict:
    run_id = uuid.uuid4().hex[:8]
    names = [f"{BENCH_PREFIX}publish-{run_id}-{i:02d}" for i in range(subscriptions)]
    for name in names:
        create_subscription(base_url, admin_token, name, [event_type])

    token = issue_credential(base_url, admin_token, f"{BENCH_PREFIX}publisher-{run_id}")

    def publish(index: int) -> dict:
        return http_call(
            "POST",
            f"{base_url}/v1/events",
            publish_envelope(index, event_type),
            token,
            timeout=30.0,
        )

    results, elapsed, total = run_load(args.duration, args.rps, publish)
    summary = load_summary(results, elapsed, total, {201})
    summary["subscriptions"] = subscriptions
    summary["event_type"] = event_type
    summary["rps_target"] = args.rps
    return summary


def scenario_b2(args, base_url: str, admin_token: str) -> dict:
    return scenario_publish(args, base_url, admin_token, 1, "bench.load")


def scenario_b3(args, base_url: str, admin_token: str) -> dict:
    return scenario_publish(args, base_url, admin_token, 50, "bench.load")


def scenario_b4(args, base_url: str, admin_token: str) -> dict:
    run_id = uuid.uuid4().hex[:8]
    subscription = f"{BENCH_PREFIX}claim-{run_id}"
    create_subscription(base_url, admin_token, subscription, ["bench.load"])
    token = issue_credential(base_url, admin_token, f"{BENCH_PREFIX}consumer-{run_id}")

    stop = threading.Event()
    lock = threading.Lock()
    visibility: list[float] = []
    consumer_errors = 0
    claims = 0
    acks = 0
    ack_errors = 0

    def consumer_worker() -> None:
        nonlocal consumer_errors, claims, acks, ack_errors
        while not stop.is_set():
            response = claim(base_url, token, subscription, args.max, args.wait_ms)
            if response["status"] != 200:
                with lock:
                    consumer_errors += 1
                continue
            payload = response_json(response) or {}
            deliveries = payload.get("deliveries", [])
            if not deliveries:
                continue
            received_at = time.time()
            with lock:
                claims += len(deliveries)
            for delivery in deliveries:
                try:
                    age_ms = (received_at - parse_iso(delivery["occurred_at"]).timestamp()) * 1000.0
                    with lock:
                        visibility.append(age_ms)
                except (KeyError, TypeError, ValueError):
                    with lock:
                        consumer_errors += 1
            for delivery in deliveries:
                result = ack(base_url, token, delivery["delivery_id"], delivery["lease_token"])
                with lock:
                    if result["status"] == 200:
                        acks += 1
                    else:
                        ack_errors += 1

    threads = [
        threading.Thread(target=consumer_worker, name=f"bench-consumer-{i}", daemon=True)
        for i in range(args.consumers)
    ]
    for thread in threads:
        thread.start()

    time.sleep(0.5)

    def publish(index: int) -> dict:
        return http_call(
            "POST",
            f"{base_url}/v1/events",
            publish_envelope(index, "bench.load"),
            token,
            timeout=30.0,
        )

    publish_results, elapsed, total = run_load(args.duration, args.rps, publish)
    stop.set()
    for thread in threads:
        thread.join(timeout=max(10.0, args.wait_ms / 1000.0 + 10.0))

    summary = load_summary(publish_results, elapsed, total, {201})
    summary.update(
        {
            "subscription": subscription,
            "consumers": args.consumers,
            "claims": claims,
            "acks": acks,
            "ack_errors": ack_errors,
            "consumer_errors": consumer_errors,
            "claim_visibility_ms": summarize(visibility),
            "rps_target": args.rps,
        }
    )
    return summary


# ---------------------------------------------------------------------------
# Scenario B5: idle parked claims
# ---------------------------------------------------------------------------


def pg_stat_statements_available(db_url: str) -> bool:
    return psql_scalar(
        db_url,
        "SELECT count(*) FROM pg_extension WHERE extname = 'pg_stat_statements';\n",
    ) == "1"


def pgss_calls(db_url: str) -> int:
    return psql_int(db_url, "SELECT COALESCE(sum(calls), 0) FROM pg_stat_statements;\n")


def pgss_delivery_calls(db_url: str) -> int:
    return psql_int(
        db_url,
        "SELECT COALESCE(sum(calls), 0) FROM pg_stat_statements "
        "WHERE query ILIKE '%FROM deliveries%';\n",
    )


def scenario_b5(args, base_url: str, admin_token: str, db_url: str) -> dict:
    run_id = uuid.uuid4().hex[:8]
    subscription = f"{BENCH_PREFIX}idle-{run_id}"
    create_subscription(base_url, admin_token, subscription, ["bench.load"])
    token = issue_credential(base_url, admin_token, f"{BENCH_PREFIX}idle-consumer-{run_id}")

    pgss = pg_stat_statements_available(db_url)
    before_total = pgss_calls(db_url) if pgss else 0
    before_delivery = pgss_delivery_calls(db_url) if pgss else 0

    stop = threading.Event()
    lock = threading.Lock()
    requests = 0
    errors = 0
    started = time.monotonic()

    def worker() -> None:
        nonlocal requests, errors
        while not stop.is_set():
            response = claim(base_url, token, subscription, args.max, args.wait_ms)
            with lock:
                requests += 1
                if response["status"] != 200:
                    errors += 1

    threads = [
        threading.Thread(target=worker, name=f"bench-idle-{i}", daemon=True)
        for i in range(args.consumers)
    ]
    for thread in threads:
        thread.start()

    try:
        time.sleep(args.duration)
    finally:
        stop.set()
        for thread in threads:
            thread.join(timeout=max(10.0, args.wait_ms / 1000.0 + 10.0))
        elapsed = time.monotonic() - started

    after_total = pgss_calls(db_url) if pgss else 0
    after_delivery = pgss_delivery_calls(db_url) if pgss else 0

    result = {
        "status": "ok",
        "subscription": subscription,
        "parked_consumers": args.consumers,
        "duration_s": round(elapsed, 2),
        "claim_requests": requests,
        "errors": errors,
    }
    if pgss:
        result["pg_stat_statements"] = {
            "available": True,
            "statements_per_s": round((after_total - before_total) / elapsed, 2),
            "delivery_statements_per_s": round((after_delivery - before_delivery) / elapsed, 2),
            "note": "Cluster-wide counters; other database activity is included.",
        }
    else:
        result["pg_stat_statements"] = {
            "available": False,
            "note": "pg_stat_statements extension is not installed; DB statement rate skipped.",
        }
    return result


# ---------------------------------------------------------------------------
# Scenario B6: backlog drain
# ---------------------------------------------------------------------------


def scenario_b6(args, base_url: str, admin_token: str, db_url: str) -> dict:
    run_id = uuid.uuid4().hex[:8]
    subscription = f"{BENCH_PREFIX}drain-{run_id}"
    create_subscription(base_url, admin_token, subscription, ["bench.seeded"])
    token = issue_credential(base_url, admin_token, f"{BENCH_PREFIX}drain-consumer-{run_id}")

    subscription_id = psql_scalar(
        db_url,
        f"SELECT id FROM subscriptions WHERE name = '{subscription}';\n",
    )
    tag = f"{BENCH_PREFIX}drain-{run_id}"
    seed_started = time.monotonic()
    seed_pending(db_url, subscription_id, args.rows, tag)
    seed_seconds = time.monotonic() - seed_started

    samples: list[tuple[float, int]] = []
    acked = 0
    batches = 0
    errors = 0
    started = time.monotonic()
    deadline = started + args.duration

    while time.monotonic() < deadline:
        response = claim(base_url, token, subscription, args.max, 0)
        if response["status"] != 200:
            errors += 1
            break
        payload = response_json(response) or {}
        deliveries = payload.get("deliveries", [])
        if not deliveries:
            break
        for delivery in deliveries:
            result = ack(base_url, token, delivery["delivery_id"], delivery["lease_token"])
            if result["status"] != 200:
                errors += 1
        acked += len(deliveries)
        batches += 1
        samples.append((time.monotonic() - started, acked))

    elapsed = time.monotonic() - started
    remaining = psql_int(
        db_url,
        f"SELECT count(*) FROM deliveries WHERE subscription_id = '{subscription_id}'::uuid "
        "AND state = 'pending';\n",
    )
    return {
        "status": "ok",
        "subscription": subscription,
        "rows_seeded": args.rows,
        "seed_seconds": round(seed_seconds, 2),
        "claimed_and_acked": acked,
        "batches": batches,
        "drain_seconds": round(elapsed, 2),
        "drain_rate_per_s": round(acked / elapsed, 2) if elapsed > 0 else 0,
        "remaining_pending": remaining,
        "completed": remaining == 0,
        "errors": errors,
        "rate_buckets": rate_buckets(samples),
    }


# ---------------------------------------------------------------------------
# Scenario B7: retention purge wall-clock
# ---------------------------------------------------------------------------


def scenario_b7(args, db_url: str, allow_shared_db: bool) -> dict:
    expired = nonbench_expired_counts(db_url)
    nonbench_total = sum(expired.values())
    if nonbench_total > 0 and not allow_shared_db:
        return skip(
            "retention purge is global and non-benchmark expired rows exist "
            f"(delivered={expired['delivered']}, terminal={expired['terminal']}, "
            f"events={expired['events']}); pass --allow-shared-db to accept that they "
            "will be deleted, or run against a dedicated benchmark database"
        )

    if not shutil.which("mix"):
        return skip("mix is not on PATH; cannot run AsnEventBroker.Retention.purge")

    run_id = uuid.uuid4().hex[:8]
    subscription = f"{BENCH_PREFIX}retention-{run_id}"
    subscription_id = str(uuid.uuid4())
    insert_bench_subscription(db_url, subscription, subscription_id)
    tag = f"{BENCH_PREFIX}retention-{run_id}"
    seed_started = time.monotonic()
    plan = seed_retention(db_url, subscription_id, args.rows, tag)
    seed_seconds = time.monotonic() - seed_started

    # --no-start plus explicit overrides keeps the purge isolated: no HTTP
    # listener, no lease reaper, and no admin bootstrap touching shared state.
    expression = (
        "Application.put_env(:asn_event_broker, :start_workers, false); "
        "Application.put_env(:asn_event_broker, :http, [enabled: false]); "
        "Application.put_env(:asn_event_broker, :bootstrap_admin, false); "
        "{:ok, _} = Application.ensure_all_started(:asn_event_broker); "
        "start = System.monotonic_time(:millisecond); "
        "result = AsnEventBroker.Retention.purge(1000); "
        "stop = System.monotonic_time(:millisecond); "
        'IO.puts("PURGE_RESULT=" <> Jason.encode!(Map.put(result, :elapsed_ms, stop - start)))'
    )
    env = os.environ.copy()
    env["BROKER_DATABASE_URL"] = db_url
    env["EVENT_BROKER_HTTP_DISABLED"] = "true"
    env.setdefault("MIX_ENV", "dev")

    started = time.monotonic()
    proc = subprocess.run(
        ["mix", "run", "--no-start", "-e", expression],
        cwd=str(BROKER_DIR),
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    wall_seconds = time.monotonic() - started

    purge = None
    for line in proc.stdout.splitlines():
        if line.startswith("PURGE_RESULT="):
            try:
                purge = json.loads(line.split("=", 1)[1])
            except ValueError:
                purge = None

    return {
        "status": "ok" if proc.returncode == 0 and purge is not None else "error",
        "subscription": subscription,
        "rows_base": args.rows,
        "seeded": {
            "delivered": plan["delivered"],
            "dead": plan["dead"],
            "extra_events": plan["extra_events"],
            "total_events": plan["total_events"],
        },
        "seed_seconds": round(seed_seconds, 2),
        "wall_seconds": round(wall_seconds, 2),
        "purge_elapsed_ms": purge.get("elapsed_ms") if purge else None,
        "purged": purge,
        "nonbench_expired_before": expired,
        "allow_shared_db": allow_shared_db,
        "stderr_tail": proc.stderr.strip().splitlines()[-5:] if proc.returncode != 0 else [],
    }


# ---------------------------------------------------------------------------
# Scenario B8: metrics scrape cost
# ---------------------------------------------------------------------------


def scenario_b8(args, base_url: str, db_url: str) -> dict:
    run_id = uuid.uuid4().hex[:8]
    subscription = f"{BENCH_PREFIX}metrics-{run_id}"
    subscription_id = str(uuid.uuid4())
    insert_bench_subscription(db_url, subscription, subscription_id)

    top = max(1, args.rows)
    targets = sorted({max(1, top // 50), max(1, top // 5), top})
    tag = f"{BENCH_PREFIX}metrics-{run_id}"
    seeded = 0
    results = []

    for target in targets:
        if target > seeded:
            seed_pending(db_url, subscription_id, target - seeded, f"{tag}-{target}")
            seeded = target

        latencies = []
        sizes = []
        statuses = []
        for _ in range(5):
            response = http_call("GET", f"{base_url}/metrics", timeout=180.0)
            statuses.append(response["status"])
            latencies.append(response["latency_ms"])
            sizes.append(len(response["body"]))

        results.append(
            {
                "target_rows": target,
                "table_counts": table_counts(db_url),
                "metrics_status": statuses,
                "latency_ms": summarize(latencies),
                "body_bytes": sizes[-1] if sizes else 0,
            }
        )

    return {
        "status": "ok",
        "subscription": subscription,
        "top_target": top,
        "targets": targets,
        "results": results,
    }


# ---------------------------------------------------------------------------
# Scenario B9: authorization cost under ack load
# ---------------------------------------------------------------------------


def find_listener_pid(port: int) -> int | None:
    commands = [
        ["ss", "-ltnp", f"sport = :{port}"],
        ["lsof", "-ti", f"tcp:{port}", "-sTCP:LISTEN"],
    ]
    for command in commands:
        if not shutil.which(command[0]):
            continue
        try:
            proc = subprocess.run(command, text=True, capture_output=True, check=False, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if proc.returncode != 0:
            continue
        match = re.search(r"pid=(\d+)", proc.stdout)
        if match:
            return int(match.group(1))
        for line in proc.stdout.splitlines():
            if line.strip().isdigit():
                return int(line.strip())
    return None


def proc_cpu_seconds(pid: int) -> float | None:
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8") as handle:
            fields = handle.read().split()
        ticks = os.sysconf("SC_CLK_TCK")
        return (int(fields[13]) + int(fields[14])) / ticks
    except (OSError, ValueError, IndexError):
        return None


def scenario_b9(args, base_url: str, admin_token: str, db_url: str) -> dict:
    run_id = uuid.uuid4().hex[:8]
    tag = f"{BENCH_PREFIX}auth-{run_id}"
    credentials = seed_credentials(db_url, 100, tag)

    subscription = f"{BENCH_PREFIX}auth-{run_id}"
    subscription_id = str(uuid.uuid4())
    insert_bench_subscription(db_url, subscription, subscription_id)

    lease_token = f"{tag}-lease"
    lease_hash = sha256_hex(lease_token)
    total_deliveries = max(args.rows, int(args.duration * args.rps) + 100)
    seed_leased(db_url, subscription_id, total_deliveries, tag, lease_token, lease_hash)

    delivery_ids = [bench_uuid(tag, "delivery", index) for index in range(1, total_deliveries + 1)]
    counter = {"index": 0}
    lock = threading.Lock()

    def next_delivery() -> str:
        with lock:
            index = counter["index"] % len(delivery_ids)
            counter["index"] += 1
            return delivery_ids[index]

    def do_ack(_index: int) -> dict:
        return ack(base_url, admin_token, next_delivery(), lease_token)

    port = urllib.parse.urlparse(base_url).port or 80
    pid = find_listener_pid(port)
    cpu_before = proc_cpu_seconds(pid) if pid else None
    started = time.monotonic()
    results, elapsed, total = run_load(args.duration, args.rps, do_ack)
    cpu_after = proc_cpu_seconds(pid) if pid else None
    wall = time.monotonic() - started

    summary = load_summary(results, elapsed, total, {200})
    summary.update(
        {
            "credentials_seeded": len(credentials),
            "subscription": subscription,
            "leased_deliveries": total_deliveries,
            "rps_target": args.rps,
            "broker_pid": pid,
            "broker_cpu": (
                {
                    "cpu_seconds": round(cpu_after - cpu_before, 2),
                    "cpu_percent": round(((cpu_after - cpu_before) / wall) * 100.0, 2),
                    "note": "Best-effort /proc sample of the listener process.",
                }
                if pid and cpu_before is not None and cpu_after is not None and wall > 0
                else {
                    "available": False,
                    "note": "Could not find the broker listener PID; broker CPU not sampled.",
                }
            ),
        }
    )
    return summary


# ---------------------------------------------------------------------------
# Orchestration and reporting
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Benchmark harness for the ASN event broker (B1-B9).",
        epilog=(
            "Per-scenario defaults: "
            "B2 100 rps/10s; B3 200 rps/10s over 50 subscriptions; "
            "B4 300 rps/10s with 20 consumers; B5 50 consumers for 600s; "
            "B6 1,000,000 pending rows; B7 1,000,000 base rows "
            "(2M delivered + 500k dead + 1M events); B8 5,000,000 top row target; "
            "B9 500 rps/10s with 100 credentials. Explicit flags always win."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--scenario", choices=SCENARIOS + ["all"], default="b1")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--db-url", default=DEFAULT_DB_URL)
    parser.add_argument("--token", default=None, help="Admin bearer token (or BROKER_ADMIN_TOKEN)")
    parser.add_argument("--duration", type=float, default=None, help="Seconds of load")
    parser.add_argument("--rps", type=float, default=None, help="Target requests per second")
    parser.add_argument("--consumers", type=int, default=None, help="Concurrent consumers")
    parser.add_argument("--max", type=int, default=None, help="Claim batch size")
    parser.add_argument("--wait-ms", type=int, default=None, help="Long-poll wait in ms")
    parser.add_argument("--rows", type=int, default=None, help="Seed/dataset size override")
    parser.add_argument(
        "--allow-nonlocal",
        action="store_true",
        help="Allow seeding/deleting against a non-local database host",
    )
    parser.add_argument(
        "--allow-shared-db",
        action="store_true",
        help="Allow fan-out to non-bench subscriptions and the global retention purge",
    )
    parser.add_argument("--output", default=None, help="Write the JSON result to this path")
    return parser.parse_args()


def scenario_args(args: argparse.Namespace, scenario: str) -> argparse.Namespace:
    """Return a per-scenario copy with that scenario's defaults filled in."""
    effective = argparse.Namespace(**vars(args))
    defaults = SCENARIO_DEFAULTS.get(scenario, SCENARIO_DEFAULTS["b2"])
    for key in ("rps", "duration", "consumers", "rows", "max"):
        if getattr(effective, key) is None:
            setattr(effective, key, defaults[key])
    if effective.wait_ms is None:
        effective.wait_ms = defaults["wait_ms"]
    return effective


def admin_token(args: argparse.Namespace) -> str | None:
    return args.token or os.environ.get("BROKER_ADMIN_TOKEN")


def require_http(base_url: str) -> bool:
    if wait_ready(base_url):
        return True
    print(
        f"    SKIP: broker is not ready at {base_url}; start it with "
        "'cd services/event-broker && mix run --no-halt'",
        file=sys.stderr,
    )
    return False


def run_scenario(args: argparse.Namespace, scenario: str, db_url: str) -> dict:
    base_url = args.base_url.rstrip("/")
    token = admin_token(args)

    if scenario == "b1":
        return scenario_b1(args, db_url)

    if scenario in SEEDING_SCENARIOS:
        cleanup_bench(db_url)

    if scenario in {"b2", "b3", "b4", "b5", "b6", "b9"} and not token:
        return skip(
            "no credential token: set BROKER_ADMIN_TOKEN or pass --token "
            "(authenticated scenarios B2/B4/B5/B6/B9 need it)"
        )

    if scenario in {"b2", "b3", "b4"}:
        nonbench = nonbench_active_subscriptions(db_url)
        if nonbench > 0 and not args.allow_shared_db:
            return skip(
                f"{nonbench} non-bench active subscription(s) exist; publishing would "
                "fan out to them. Use a dedicated benchmark database or pass "
                "--allow-shared-db."
            )

    if scenario in {"b2", "b3", "b4", "b5", "b6", "b8", "b9"} and not require_http(base_url):
        return {"status": "skipped", "note": f"broker not ready at {base_url}"}

    if scenario == "b2":
        return scenario_b2(args, base_url, token)
    if scenario == "b3":
        return scenario_b3(args, base_url, token)
    if scenario == "b4":
        return scenario_b4(args, base_url, token)
    if scenario == "b5":
        return scenario_b5(args, base_url, token, db_url)
    if scenario == "b6":
        return scenario_b6(args, base_url, token, db_url)
    if scenario == "b7":
        return scenario_b7(args, db_url, args.allow_shared_db)
    if scenario == "b8":
        return scenario_b8(args, base_url, db_url)
    if scenario == "b9":
        return scenario_b9(args, base_url, token, db_url)
    raise ValueError(f"unknown scenario {scenario}")


def render_markdown(results: dict, meta: dict) -> str:
    lines = [
        "# Event broker benchmark summary",
        "",
        f"- Generated: `{meta['generated_at']}`",
        f"- Database: `{meta['db_url']}` (credentials redacted)",
        f"- Broker: `{meta['base_url']}`",
        f"- Scenarios: `{', '.join(results)}`",
        "",
    ]

    for scenario, result in results.items():
        lines.append(f"## {scenario.upper()}")
        lines.append("")
        if result.get("status") == "skipped":
            lines.append(f"**Skipped:** {result.get('note', '')}")
            lines.append("")
            continue
        if result.get("status") == "error":
            lines.append(f"**Error:** {result.get('error', 'unknown error')}")
            lines.append("")
            continue

        if scenario == "b1":
            lines.append("| check | seq scan | index scan | execution ms |")
            lines.append("|---|---|---|---|")
            for name, check in result["checks"].items():
                lines.append(
                    f"| `{name}` | {'yes' if check['seq_scan'] else 'no'} | "
                    f"{'yes' if check['index_scan'] else 'no'} | "
                    f"{check['execution_ms'] if check['execution_ms'] is not None else '-'} |"
                )
            lines.append("")
            for name, check in result["checks"].items():
                lines.append(f"### Plan: `{name}`")
                lines.append("")
                plan_lines = check["plan"].splitlines()[:30]
                lines.append("```text")
                lines.extend(plan_lines)
                if len(check["plan"].splitlines()) > 30:
                    lines.append("... (full plan in JSON)")
                lines.append("```")
                lines.append("")
            lines.append(f"Table rows: `{json.dumps(result['table_counts'], sort_keys=True)}`")
            lines.append("")
            continue

        if scenario in {"b2", "b3", "b4"}:
            latency = result.get("latency_ms", {})
            lines.append(
                f"- target: `{result.get('rps_target')} rps`, requests: `{result.get('requests')}`, "
                f"actual: `{result.get('rps_actual')} rps`, error rate: `{result.get('error_rate')}`"
            )
            lines.append(
                f"- publish latency ms: p50 `{latency.get('p50')}`, p95 `{latency.get('p95')}`, "
                f"p99 `{latency.get('p99')}`, max `{latency.get('max')}`"
            )
            if scenario == "b3":
                lines.append(f"- subscriptions: `{result.get('subscriptions')}`")
            if scenario == "b4":
                visibility = result.get("claim_visibility_ms", {})
                lines.append(
                    f"- consumers: `{result.get('consumers')}`, claims: `{result.get('claims')}`, "
                    f"acks: `{result.get('acks')}`, ack errors: `{result.get('ack_errors')}`"
                )
                lines.append(
                    f"- claim visibility ms: p50 `{visibility.get('p50')}`, p95 "
                    f"`{visibility.get('p95')}`, p99 `{visibility.get('p99')}`, "
                    f"max `{visibility.get('max')}`"
                )
            lines.append("")
            continue

        if scenario == "b5":
            lines.append(
                f"- parked consumers: `{result.get('parked_consumers')}`, duration: "
                f"`{result.get('duration_s')}s`, claim requests: `{result.get('claim_requests')}`, "
                f"errors: `{result.get('errors')}`"
            )
            pgss = result.get("pg_stat_statements", {})
            if pgss.get("available"):
                lines.append(
                    f"- DB statements/s: `{pgss.get('statements_per_s')}` "
                    f"(delivery-related `{pgss.get('delivery_statements_per_s')}`)"
                )
            else:
                lines.append(f"- pg_stat_statements: {pgss.get('note')}")
            lines.append("")
            continue

        if scenario == "b6":
            lines.append(
                f"- seeded: `{result.get('rows_seeded')}` in `{result.get('seed_seconds')}s`; "
                f"drained `{result.get('claimed_and_acked')}` in `{result.get('drain_seconds')}s` "
                f"(`{result.get('drain_rate_per_s')}/s`); remaining `{result.get('remaining_pending')}`"
            )
            lines.append(f"- completed: `{result.get('completed')}`, errors: `{result.get('errors')}`")
            lines.append("")
            continue

        if scenario == "b7":
            lines.append(
                f"- seeded delivered `{result['seeded']['delivered']}`, dead "
                f"`{result['seeded']['dead']}`, extra events `{result['seeded']['extra_events']}`"
            )
            lines.append(
                f"- seed: `{result.get('seed_seconds')}s`, purge: `{result.get('purge_elapsed_ms')}ms`, "
                f"wall: `{result.get('wall_seconds')}s`"
            )
            lines.append(f"- purged: `{json.dumps(result.get('purged'), sort_keys=True)}`")
            lines.append("")
            continue

        if scenario == "b8":
            lines.append("| target rows | metrics p50 ms | p95 ms | p99 ms | body bytes |")
            lines.append("|---|---|---|---|---|")
            for item in result["results"]:
                latency = item["latency_ms"]
                lines.append(
                    f"| {item['target_rows']} | {latency.get('p50')} | {latency.get('p95')} | "
                    f"{latency.get('p99')} | {item['body_bytes']} |"
                )
            lines.append("")
            continue

        if scenario == "b9":
            latency = result.get("latency_ms", {})
            lines.append(
                f"- credentials: `{result.get('credentials_seeded')}`, target: "
                f"`{result.get('rps_target')} rps`, actual: `{result.get('rps_actual')} rps`, "
                f"error rate: `{result.get('error_rate')}`"
            )
            lines.append(
                f"- ack latency ms: p50 `{latency.get('p50')}`, p95 `{latency.get('p95')}`, "
                f"p99 `{latency.get('p99')}`, max `{latency.get('max')}`"
            )
            cpu = result.get("broker_cpu", {})
            if cpu.get("available") is False:
                lines.append(f"- broker CPU: {cpu.get('note')}")
            else:
                lines.append(
                    f"- broker CPU: `{cpu.get('cpu_percent')}%` "
                    f"(`{cpu.get('cpu_seconds')}s` over the run)"
                )
            lines.append("")
            continue

        lines.append(f"```json\n{json.dumps(result, indent=2, sort_keys=True)}\n```")
        lines.append("")

    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    db_url = args.db_url
    base_url = args.base_url.rstrip("/")

    host = db_host(db_url)
    if host not in LOCAL_HOSTS and not args.allow_nonlocal:
        print(
            f"REFUSED: database host is {host!r}, not localhost/127.0.0.1/::1. "
            "Pass --allow-nonlocal only for a dedicated benchmark database.",
            file=sys.stderr,
        )
        return 2

    if not shutil.which("psql"):
        print("REFUSED: psql is not on PATH (required for seeding and plan checks).", file=sys.stderr)
        return 2

    try:
        require_psql(db_url)
    except RuntimeError as exc:
        print(f"REFUSED: {exc}", file=sys.stderr)
        return 2

    scenarios = SCENARIOS if args.scenario == "all" else [args.scenario]
    results: dict = {}
    notes: list[str] = []

    for scenario in scenarios:
        print(f"==> {scenario.upper()}", file=sys.stderr)
        effective = scenario_args(args, scenario)
        try:
            results[scenario] = run_scenario(effective, scenario, db_url)
        except KeyboardInterrupt:
            results[scenario] = {"status": "error", "error": "interrupted"}
            notes.append(f"{scenario}: interrupted")
            break
        except Exception as exc:  # noqa: BLE001 - report, do not hide
            results[scenario] = {"status": "error", "error": str(exc)}
            notes.append(f"{scenario}: {exc}")
        finally:
            if scenario in SEEDING_SCENARIOS:
                try:
                    cleanup_bench(db_url)
                except Exception as exc:  # noqa: BLE001 - cleanup failure is reported
                    notes.append(f"{scenario}: cleanup failed: {exc}")

    meta = {
        "generated_at": iso_now(),
        "db_url": redact_url(db_url),
        "base_url": base_url,
        "python": sys.version.split()[0],
        "notes": notes,
    }
    document = {"meta": meta, "scenarios": results}

    print(render_markdown(results, meta))

    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nJSON written to `{output_path}`")
    else:
        print("\n## JSON\n")
        print("```json")
        print(json.dumps(document, indent=2, sort_keys=True))
        print("```")

    if notes:
        print("\n## Notes")
        for note in notes:
            print(f"- {note}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
