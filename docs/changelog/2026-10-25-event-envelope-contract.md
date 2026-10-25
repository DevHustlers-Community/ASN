---
date: 2026-10-25
type: feat
scope: contracts
summary: Add the canonical event envelope JSON Schema, the first event contract artifact
breaking: false
adr: "0008"
contracts: events/common/event-envelope.schema.json
---

# Add the canonical event envelope schema

## Change

- Added `contracts/events/common/event-envelope.schema.json` (JSON Schema
  draft 2020-12): the canonical envelope carried by every ASN event. Required
  fields are `event_id` (UUIDv7), `type` (dotted lowercase), `schema_version`,
  `occurred_at` (RFC 3339 UTC), and `payload` (object). Aggregate fields
  `aggregate_type`/`aggregate_id`/`aggregate_version` are all-or-none and, when
  present, `aggregate_version` is strictly increasing and unique per aggregate
  — one event per version is a deliberate event-model constraint. `trace_id`
  is optional. Unknown envelope fields are rejected
  (`additionalProperties: false`).
- Updated `contracts/events/README.md`: replaced the "not written yet" status
  with the landed-envelope status and added transport notes binding the
  envelope to the delivery contract (publisher identity from credentials,
  `content_hash` idempotency with 200/409 semantics, the 256 KiB whole-body
  limit with claim-check references, and mandatory consumer-side dedup on
  `event_id` with `aggregate_version` staleness checks).

## Why

ADR 0008 (accepted) requires the event envelope as the first contract artifact
before any broker proof of concept, per the events contracts README. The
schema fixes the wire shape publishers must produce and consumers must accept,
and encodes the identity and ordering rules settled during the ADR review
rounds so the implementing agent never has to invent them.

## Verification

- `python3 scripts/ci/check-links.py` — run; see output in the session record.
- `python3 scripts/ci/check-changelog.py --all` — run; see output in the
  session record.
- Contract validation tooling under `scripts/contracts/` does not exist yet
  (per AGENTS.md §7); schema syntax was verified as JSON and reviewed by hand.
  Client generation does not apply to this artifact yet.

## Follow-ups

- Add per-event payload schemas (`social/*.v1.schema.json`, `chat/*.v1.schema.json`,
  `moderation/*.v1.schema.json`) before each producing feature is implemented.
- Broker migrations and the publish/claim/ack vertical slice implement this
  envelope next, per ADR 0008.
