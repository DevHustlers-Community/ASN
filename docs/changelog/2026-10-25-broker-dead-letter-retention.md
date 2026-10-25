---
date: 2026-10-25
type: feat
scope: services
summary: Add dead-letter replay/skip with the audit log and dependency-aware retention
breaking: false
adr: "0008"
contracts: -
---

# Add dead-letter admin actions and dependency-aware retention

## Change

- Added `DeadLetter.replay/skip/list_dead` (ADR 0008 §3, §5, §9): replay
  returns a dead delivery to `pending` with attempts reset to zero; skip is a
  terminal operator decision. Both are recorded in the new `Audit` module —
  an append-only entry written in the same `broker_db` transaction as the
  state change, with the actor credential id as a soft reference. Replaying
  or skipping an earlier dead version releases the aggregate (head-of-line).
- Added `Retention.purge/1`: batched, dependency-aware purge — delivered
  deliveries after 24 hours, dead/skipped after 30 days, events only past the
  7-day log floor AND with no delivery still within its own retention window,
  so events backing live dead letters survive the full replay window. Retention
  values are runtime configuration.
- Integration tests: replay with fresh budget releasing blocked versions,
  audit entry contents, skip terminality, not-dead/not-found errors, dead
  listing, and the retention interaction matrix (fresh delivered keeping an
  old event alive, event purged once no delivery needs it, live dead letters
  surviving the terminal window).

## Why

These are the operational halves of the ADR: dead letters are states, replay
is audited and admin-scoped, and retention must never orphan a replayable
delivery.

## Verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test` — run; 46/46 pass.
- `python3 scripts/ci/check-changelog.py --all` — run; pass.

## Follow-ups

- Phase 6: OpenAPI contract, then the Plug/Bandit HTTP edge with bearer-token
  auth; phase 7 telemetry; phase 8 chat outbox relay; phase 9 property tests.
