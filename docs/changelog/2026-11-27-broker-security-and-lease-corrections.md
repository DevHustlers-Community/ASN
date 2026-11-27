---
date: 2026-11-27
type: fix
scope: broker
summary: Enforce Broker consumer isolation, credential expiry, auditing, and lease backoff
breaking: false
adr: 0008
contracts: contracts/openapi/event-broker-api.yaml
---

# Broker security and lease-lifecycle corrections

## Change

- Bound claim, ack, nack, and extend operations to credentials whose
  `service_name` matches the subscription's `consumer`. Cross-service and
  unknown resources return `404`; missing consume scope remains `403`.
- Credential issuance now parses and persists `expires_at`, rejects malformed or
  past timestamps, and includes expiry in the creation audit record.
- Subscription creation now writes `subscription.create` in the same transaction
  as the insert. The Ecto schema mirrors the database's `max_attempts: 5`
  default so responses and audit records show the effective value.
- The lease reaper uses PostgreSQL `clock_timestamp()` and one batched SQL
  statement to apply the configured jittered exponential backoff.
- Updated OpenAPI descriptions and responses, Broker documentation, and the
  benchmark harness so `bench-load` credentials match their subscriptions.
- Added HTTP, security, delivery, and audit tests covering same-service success,
  cross-service denial without state mutation, expiry, subscription defaults,
  reaper backoff, and exhausted attempts.

## Why

The previous edge allowed any consume-scoped service to read or mutate another
service's deliveries, ignored documented credential expiry, omitted subscription
creation audit records, and retried crashed consumers immediately without the
backoff required by ADR 0008.

## Verification

- `mix format --check-formatted` and `mix compile --warnings-as-errors` — clean.
- Full Broker `mix test` — 109 passed, including 3 properties.
- `mix hex.audit` — no retired or security advisory packages.
- Benchmark B4 smoke against `broker_db_test` — 2 publishes, 2 claims, 2 acks,
  zero consumer or acknowledgement errors.
- `python3 scripts/contracts/validate.py --base-ref origin/main` — contracts
  validation OK.
