---
date: 2026-10-25
type: feat
scope: services
summary: Add broker Ecto schemas and envelope validation with canonical content hashing
breaking: false
adr: "0008"
contracts: events/common/event-envelope.schema.json
---

# Add broker Ecto schemas and envelope validation

## Change

- Added the five Ecto schemas over the migrated `broker_db` tables:
  `Events.Event`, `Subscriptions.Subscription`, `Delivery.Delivery`
  (states and statuses as `Ecto.Enum`, aggregate columns denormalized as per
  the schema design), `Security.ServiceCredential`, and `Audit.AuditEntry`.
  Timestamps map to the repo convention (`created_at`/`updated_at`,
  `utc_datetime_usec`).
- Added `Events.Envelope`: canonical envelope validation mirroring
  `contracts/events/common/event-envelope.schema.json` (required fields,
  dotted-lowercase type pattern, all-or-none aggregate fields, unknown-field
  rejection) and `content_hash/1` — SHA-256 over the full envelope serialized
  as JSON with recursively sorted keys, so a producer's key order can never
  turn an identical event into a 409 conflict.
- Added `UUIDv7`, a minimal RFC 9562 UUIDv7 generator (48-bit unix-ms, version
  7, variant 10). **Flagged decision:** the built-in OTP runtime provides no
  UUID module, so this internal implementation stands in behind a single
  `generate/0` interface until the UUIDv7 library decision for Elixir
  (architecture §9, item 16) is settled; swapping it later changes one module.
- Added `jason` dependency for `jsonb` handling and canonical encoding.
- Unit tests for UUIDv7 format/uniqueness/monotonic timestamps and envelope
  validation/hashing, including key-order stability of the content hash.

## Why

ADR 0008 (accepted) requires validated envelopes and content-hash publish
integrity before the publish path can exist; the schemas are the typed
boundary over the applied migration.

## Verification

- `mix deps.get`, `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix test` — run; 16/16 pass
  (integration-backed sandbox tests included via `mix test` alias migrating
  `broker_db_test`).
- `python3 scripts/ci/check-changelog.py --all` and `check-links.py` — run;
  pass.

## Follow-ups

- Publishing (201/200/409/422) and fan-out land next on these schemas.
- Replace `UUIDv7` with the vetted library when §9 item 16 is decided.
