---
date: 2026-11-09
type: feat
scope: chat
summary: Implement the Chat accounts projection lock and devices context with outbox events
breaking: false
adr: -
contracts: -
---

# Implement the Chat accounts projection lock and devices context with outbox events

## Change

- Added `AsnChat.Accounts` and `AsnChat.Accounts.User`, a read-only projection of
  `chat_users` that exposes `lock_user/1`. The lock uses `FOR NO KEY UPDATE` and
  must run inside the caller's transaction, serializing device mutations per user
  without blocking foreign-key key-share checks.
- Added `AsnChat.Devices`, `AsnChat.Devices.Device`, and `AsnChat.Devices.Events`:
  - `register_device/3` locks the user, creates a UUIDv7 device, and writes one
    `chat.device.registered` outbox event in the same transaction. A retry with
    the same active fingerprint and byte-identical public key returns the
    existing device without a second event; different key bytes for the same
    active fingerprint return `{:error, :identity_key_conflict}` and write
    nothing. A revoked fingerprint may be registered again as a new device.
  - `revoke_device/3` locks the user and device, writes one
    `chat.device.revoked` event, and is idempotent for an already revoked device.
    Unknown devices and devices owned by another user both return
    `{:error, :not_found}`.
  - `list_devices/1` returns the caller's devices, including revoked ones,
    ordered by `created_at` then `id`.
  - Registration and revocation accept an optional `trace_id`; outbox failures
    roll back the business change. Event payloads carry identifiers and platform
    only, never public key bytes or device labels.
- Added `test/support/chat_fixtures.ex` and imported it from
  `AsnChat.DataCase`.
- Added unit tests for device changesets and event envelopes, real-PostgreSQL
  integration tests for accounts and device lifecycle/outbox behavior, and
  unboxed concurrency race tests for registration and revocation under
  `test/failure/`.
- Updated `services/chat-service/README.md` and `CODE_MAP.md` to record the
  implemented contexts and the new test layers.

No migration or contract change: `chat_devices`, the partial unique index, and
the device event contracts already exist.

## Why

The device registry is the first Chat domain slice that can land without
resolving the E2EE storage decisions: it persists only public protocol material
and emits the already-committed device events. Per-user locking on the
`chat_users` row keeps retries and concurrent revocations serialized without a
global writer, while the partial unique index remains the database backstop.
Controllers and routes stay out of scope until the authentication decision in
architecture §9.1.

## Verification

- `docker compose up -d postgres` — PostgreSQL 18.6 reported `healthy`.
- `services/chat-service`: `mix format --check-formatted` — clean;
  `mix compile --warnings-as-errors` — clean; `mix test` — 100 passed (the test
  alias creates and migrates `chat_db_test` against the real local PostgreSQL,
  and the race tests bypass the SQL sandbox).
- `python3 scripts/contracts/validate.py --base-ref upstream/main` — both
  OpenAPI files OK; 5 event schema(s), 6 valid and 4 invalid examples, 4 payload
  bindings.
- `python3 scripts/ci/check-links.py` — relative documentation links OK.
- `python3 scripts/ci/check-changelog.py --all` — change records OK.

## Follow-ups

- **HTTP surface:** device controllers, routes, and authentication wait on
  architecture §9.1. Until then the context is unreachable over HTTP.
- **Prekeys:** device prekey storage and publication remain blocked by
  ADR 0007 and the planned ADR 0009; `devices` currently owns the registry only.
- **Accounts projection:** there is no Social-to-Chat projection consumer yet;
  `chat_users` rows are inserted by fixtures and, in production, must be
  populated by that consumer.
- **Timestamp type debt:** existing Chat migrations use `timestamp without time
  zone` for `created_at`/`updated_at` columns, while the repository convention
  requires `timestamptz` in UTC. Align these columns in a dedicated forward-only
  migration rather than widening this slice.
