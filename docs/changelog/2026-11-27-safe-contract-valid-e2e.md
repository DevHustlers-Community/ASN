---
date: 2026-11-27
type: test
scope: e2e
summary: Harden Broker relay E2E and generate a contract-valid Chat device event
breaking: false
adr: 0008
contracts: contracts/events/chat/chat.device.registered.v1.schema.json
---

# Safe, contract-valid Broker relay E2E

## Change

- Restricted the E2E script to loopback PostgreSQL URLs with `_test` database
  names and an explicit `E2E_ALLOW_DESTRUCTIVE=1` opt-in.
- Moved CI to `broker_db_test` and `chat_db_test` and added a negative safety
  check that rejects a development database before migration or truncation.
- Removed `fuser -k` and fixed `/tmp` paths; the script now uses a per-run
  temporary directory, terminates only its own broker child, and truncates its
  dedicated test state on exit so later ExUnit runs start clean.
- Added `tests/e2e/seed_chat_device.exs`, which registers a device through the
  real Chat devices context and reads the transactional outbox event.
- The E2E now verifies a UUIDv7 `chat.device.registered` event with the correct
  device aggregate and required public metadata payload.
- Credential issuance in the E2E now exercises a future `expires_at`, and the
  consuming credential belongs to `chat-service`.

## Why

The previous harness could truncate arbitrary configured databases, kill an
unrelated listener, and published a hand-built event that violated the event
schema. A green result did not prove the real producer path or contract
compatibility.

## Verification

- `bash -n tests/e2e/broker-relay.sh` — clean.
- `mix format --check-formatted tests/e2e/seed_chat_device.exs` from the Chat
  service — clean.
- Full local E2E against `broker_db_test` and `chat_db_test` — passed.
- Post-E2E row counts in both test databases — zero, confirming cleanup.
- Negative safety run with `chat_db` — rejected before mutation with the expected
  database-name guard error.
- Contract validation — OK.
