---
date: 2026-10-25
type: feat
scope: services
summary: Add idempotent publish with fan-out routing (201/200/409/422 semantics)
breaking: false
adr: "0008"
contracts: -
---

# Add idempotent publish and fan-out routing

## Change

- Added `Publishing.publish/2`: one transaction inserts the event and one
  delivery per eligible subscription. Exact ADR 0008 §5 semantics: new
  `event_id` → `:created`; same `event_id` with the same stored `content_hash`
  and publisher → `:duplicate`; differing content or publisher → `:conflict`;
  a different `event_id` reusing an `aggregate_version` →
  `:aggregate_version_taken`. `ON CONFLICT DO NOTHING` without a conflict
  target swallows both unique conflicts; the row is re-read to distinguish
  them.
- Added `Routing.eligible_subscriptions/1` (active-or-paused status with the
  `event_types` filter; paused subscriptions keep receiving deliveries per
  ADR §7 — only claiming is blocked).
- Denormalized aggregate columns and subscription `max_attempts` are copied
  into delivery rows at fan-out.
- Integration tests on real PostgreSQL: the four publish outcomes, fan-out
  eligibility, duplicate without new deliveries, equivalent timestamp
  representations collapsing to a duplicate while a one-microsecond difference
  is a conflict, and concurrent duplicate publishes serialized to one
  `:created` and one `:duplicate`.

## Why

This is the publish half of the vertical slice; the content-hash integrity and
aggregate-version uniqueness rules settled in the ADR review rounds are now
enforced in code and proven against a real database.

## Verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test` — run; 25/25 pass, and `broker_db_test` verified empty after the
  suite (no sandbox leaks: concurrency tests explicitly share the test's
  sandbox owner through `Ecto.Adapters.SQL.Sandbox.allow/3` with a start gate).
- `python3 scripts/ci/check-changelog.py --all` and `check-links.py` — run;
  pass.

## Follow-ups

- Claim/lease/ack machinery lands next; then retries, dead letters, and the
  HTTP edge.
