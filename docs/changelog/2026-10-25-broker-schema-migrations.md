---
date: 2026-10-25
type: feat
scope: services
summary: Add the initial broker_db schema migrations for events, subscriptions, deliveries, credentials, and audit log
breaking: false
adr: "0008"
contracts: -
---

# Add the initial broker_db schema migrations

## Change

- Added
  `services/event-broker/priv/repo/migrations/20261025120000_create_broker_schema.exs`
  creating the five broker-owned tables per ADR 0008:
  - `events`: durable log keyed by `event_id` (UUIDv7, app-generated),
    including `content_hash` (SHA-256 hex), publisher, aggregate fields, and
    the partial unique index `events_one_event_per_aggregate_version` enforcing
    one event per `(aggregate_type, aggregate_id, aggregate_version)`; the
    all-or-none aggregate-fields CHECK mirrors the envelope contract.
  - `subscriptions`: durable subscription definitions with
    `active`/`paused` status, NULL-or-non-empty `event_types`, and positive
    `max_attempts`.
  - `deliveries`: per-(subscription, event) delivery rows with the
    `pending`/`leased`/`delivered`/`dead`/`skipped` state machine, state/field
    pairing CHECKs (`lease_expires_at` iff `leased`, `lease_token_hash` when
    `leased` or `delivered`, `delivered_at`/`dead_lettered_at`/`skipped_at`
    iff their states), the unique `(subscription_id, event_id)` duplicate
    guard, and the partial unique index `deliveries_one_leased_per_aggregate`
    enforcing one lease per aggregate at the database level. Claim, reaper,
    and dead-letter inspection partial indexes included. Table is update-hot:
    `fillfactor=80` with a tightened autovacuum scale factor.
  - `service_credentials`: hashed per-service tokens with `publish`/`consume`/
    `admin` scopes (array CHECK against the known scope set), optional
    `allowed_event_types`, expiry, and revocation — multiple active
    credentials per service supported for rotation.
  - `audit_log`: append-only admin action records with actor credential id,
    action, target, params, and timestamp.
- Foreign keys from `deliveries` to `subscriptions` and `events` use
  `ON DELETE RESTRICT`: retention is dependency-aware and never orphans a
  live delivery.

## Why

ADR 0008 (accepted) defines the delivery contract; this migration gives it its
persistent shape so the publish/claim/ack vertical slice can land next. UUIDv7
generation stays in application code per ADR 0011; no database-side defaults
generate identifiers.

## Verification

- `mix ecto.create && mix ecto.migrate` — run against local PostgreSQL 18.6
  (`broker_db`); migration applied.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test` — run; all pass (`mix test` also migrates `broker_db_test`
  successfully).
- Constraint behavior proven against real PostgreSQL inside rolled-back
  transactions: duplicate delivery guard fired on repeated
  `(subscription_id, event_id)`; `deliveries_delivered_at_matches_state`
  rejected a delivered row without `delivered_at`;
  `events_one_event_per_aggregate_version` rejected a reused aggregate
  version; `deliveries_one_leased_per_aggregate` rejected a second leased
  delivery for the same aggregate;
  `events_aggregate_fields_all_or_none` rejected a partially-filled aggregate.
- `python3 scripts/ci/check-links.py` and
  `python3 scripts/ci/check-changelog.py --all` — run; pass.

## Follow-ups

- Implement the publish/claim/ack vertical slice (Ecto schemas and queries
  for these tables) per ADR 0008, with integration tests for the claim
  concurrency paths (subscription-row lock plus the leased-per-aggregate
  invariant).
- Lease reaper, retries, dead-letter replay/skip, dependency-aware retention,
  and credential bootstrap follow.
