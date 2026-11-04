---
date: 2026-11-04
type: fix
scope: broker
summary: Scope the security probe query assertion to its own token hash
breaking: false
adr: -
contracts: -
---

# Scope the security probe query assertion to its own token hash

## Change

- [`services/event-broker/test/unit/security_test.exs`](../../services/event-broker/test/unit/security_test.exs):
  the authorization probe now collects `metadata.source`, `metadata.query`, and
  `metadata.params` from the `[:asn_event_broker, :repo, :query]` telemetry
  event and keeps only the `SELECT` on `service_credentials` whose first bound
  parameter is this test's token hash.

## Why

`SecurityTest` is `async: true`, so the telemetry handler attached by this test
also receives statements from every other test running concurrently. Other
tests issue, revoke, and authorize their own credentials, and each of those
touches `service_credentials`. The assertion counted all of them, so it failed
whenever a concurrent test emitted a credential statement inside the probe
window:

```text
test/unit/security_test.exs:55
assert length(queries) == 1
left:  2
right: 1
```

That is what failed Broker run 41911722627 on `main` at `c969e653` (102 of 103
tests passed); the same commit passed locally three times in a row.

The presented token hash is unique to this test, and only the `authorize`
lookup binds it first, so filtering on it removes the shared global state
without serialising the suite or weakening the assertion: a second statement
for the same credential still fails the test, and the `token_hash` predicate is
still required.

The previous `Process.sleep(50)` was also removed; Ecto runs telemetry handlers
in the querying process, so the statements are already in the mailbox when
`Security.authorize/1` returns.

## Verification

- `mix test test/unit/security_test.exs --max-cases 24`: 7 passed, three times.
- `mix test --max-cases 24`: 103 passed (3 properties, 100 tests), ten
  consecutive runs with random seeds.
- `mix format --check-formatted` and `mix compile --warnings-as-errors`: pass.
- Local PostgreSQL 18.6 via `docker compose up -d postgres`; the suite used its
  default `broker_db_test`.

## Follow-ups

- No product behavior changes; this is a test-only fix.
