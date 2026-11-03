---
date: 2026-11-04
type: perf
scope: broker
summary: Broker authorizes credentials with an indexed token-hash lookup instead of a per-request scan
breaking: false
adr: docs/decisions/0008-broker-transport-and-delivery-contract.md
contracts: -
---

# Broker authorizes credentials with an indexed token-hash lookup instead of a per-request scan

## Change

`Security.authorize/1` in `services/event-broker` no longer loads every
non-revoked, unexpired credential per request for `Enum.find` + constant-time
compare. It now presents the presented token's SHA-256 hash to PostgreSQL as
`WHERE token_hash = $1` together with the same revoked/expired filters, so the
lookup goes through the existing unique index
`service_credentials_token_hash_index` and fetches at most one row
(`Repo.one/1`). The revoked/expired filters stayed in SQL, and the
constant-time `:crypto.hash_equals/2` comparison on the returned row is kept
as the authorization decision. Valid, revoked, expired, and unknown tokens all
return the same `{:error, :unauthorized}` shape exactly as before — error
behaviour is unchanged. A new unit test file
(`test/unit/security_test.exs`) covers the four cases plus the header edge
cases. No migration, contract, or dependency change.

## Why

Issue #7: authorization cost is O(credentials) CPU on every publish, claim,
and ack request (baseline B9: 500 rps acks with 100 credentials produced
broker CPU 217% in earlier runs), and the unique index on
`service_credentials(token_hash)` was not used by the credential query.

Timing safety: the presented bearer token is attacker-controlled and the set
of issued token hashes is not secret, so using the unique index lookup does
not disclose valid credentials — an attacker can already probe the index at
leisure without the change. There is no early return that distinguishes a
missing row from a row failing the revoked/expired filters, and the
constant-time compare on the returned row is retained. The lookup itself
runs one indexed `token_hash = $1` comparison in PostgreSQL and leaks
nothing about non-matching credentials.

## Verification

- `mix format --check-formatted` — passed.
- `mix compile --warnings-as-errors` — passed.
- `mix test` — 93 passed (3 properties, 90 tests), no failures.
- `EXPLAIN (ANALYZE, BUFFERS)` on `broker_bench` (100 seeded credentials):
  new lookup is an `Index Scan using service_credentials_token_hash_index`
  with `Index Cond: (token_hash = ...)` (2 shared-buffer hits); the previous
  shape is a `Seq Scan` reading all 100 rows.
- B9 (`scripts/dev/broker-load.py --scenario b9`, broker on the dedicated
  `broker_bench` database, 100 credentials, before vs after, two samples
  each): broker CPU 169.52%/181.71% before, 118.02%/120.5% after (roughly
  -30% relative). Achieved request rate stayed in the same band
  (381–407 rps before, 346–350 rps after): at B9's scale the remaining
  bottleneck is socket/pool contention between the drive POST and the ack
  UPDATE (connection-queue waits of 50–100 ms dominate p50), so throughput
  does not rise from this change alone while broker CPU per request drops
  measurably.
- `python3 scripts/ci/check-changelog.py --all` — passed.
- `python3 scripts/ci/check-links.py` — passed.
