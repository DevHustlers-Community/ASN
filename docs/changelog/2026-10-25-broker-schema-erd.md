---
date: 2026-10-25
type: docs
scope: services
summary: Add the broker_db ERD and delivery state diagram to the event broker documentation
breaking: false
adr: "0008"
contracts: -
---

# Add the broker_db ERD to the event broker documentation

## Change

- Added a `Schema (broker_db)` section to `services/event-broker/README.md`
  containing a Mermaid entity-relationship diagram of the five tables created
  by migration `20261025120000_create_broker_schema` (`events`,
  `subscriptions`, `deliveries`, `service_credentials`, `audit_log`) with
  column-level annotations, plus a Mermaid delivery state diagram
  (`pending`/`leased`/`delivered`/`dead`/`skipped` with admin replay and skip).
- Distinguished enforced foreign keys (`ON DELETE RESTRICT`) from soft
  references matched by value (`publisher`, `consumer`,
  `actor_credential_id`), and documented the structural invariants the
  diagram cannot express: the duplicate-delivery guard, the
  one-leased-per-aggregate and one-event-per-aggregate-version partial unique
  indexes, the absence of `ON DELETE CASCADE`, and app-generated UUIDv7
  identifiers.

## Why

The schema is now the broker's persistent contract; a visual reference in the
owning service README makes the ERD and state machine reviewable without
reading the migration, and keeps GitHub rendering for future contributors.

## Verification

- `python3 scripts/ci/check-links.py` and
  `python3 scripts/ci/check-changelog.py --all` — run; pass.
- Diagram content cross-checked against the applied migration in `broker_db`
  (tables, columns, constraints, and indexes verified earlier in the same
  session). No code or migration changes.

## Follow-ups

- Keep the section in sync when later migrations extend the schema (for
  example partitioning or new operational tables).
