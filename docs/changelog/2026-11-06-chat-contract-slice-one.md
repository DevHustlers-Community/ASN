---
date: 2026-11-06
type: feat
scope: contracts
summary: Land the first protocol-neutral Chat contract slice (OpenAPI, event schemas, migrations)
breaking: false
adr: "0007"
contracts: contracts/openapi/chat-api.yaml, contracts/events/chat/*
---

# Land the first protocol-neutral Chat contract slice (OpenAPI, event schemas, migrations)

## Change

- Added [`contracts/openapi/chat-api.yaml`](../../contracts/openapi/chat-api.yaml)
  (OpenAPI 3.1, server `/api/v1`, RFC 9457 Problem Details with stable error
  codes): `POST /devices`, `GET /devices`, `POST /devices/{deviceId}/revoke`,
  `POST /conversations`, `GET /conversations`, `GET /conversations/{id}`,
  `GET /conversations/{id}/members`, `POST /conversations/{id}/messages`,
  `GET /conversations/{id}/messages`, and
  `POST /conversations/{id}/read-cursor`. Message request/response payloads are
  opaque envelopes only (`OpaquePayload`/`Base64Bytes`); there is no plaintext
  `body` field anywhere. A 256 KiB request body limit is documented for device
  registration and message send, aligned with ADR 0008. Chat authentication is
  documented as provisional pending architecture §9.1.
- Added four Chat v1 payload schemas under [`contracts/events/chat/`](../../contracts/events/chat/):
  `chat.device.registered.v1`, `chat.device.revoked.v1`,
  `chat.conversation.created.v1` (one shot, no aggregate fields), and
  `chat.message.created.v1` (aggregate `message`; rationale encoded in the
  description). Added four valid envelope fixtures under
  [`contracts/events/examples/`](../../contracts/events/examples/) containing
  identifiers and metadata only.
- Added seven protocol-neutral `chat_db` migrations under
  `services/chat-service/priv/repo/migrations/`: `chat_users`,
  `conversations`, `conversation_members`, `chat_devices` (with the active
  fingerprint partial unique index and the `(id, user_id)` unique index),
  `messages` (with the composite FKs to pin devices to owners and replies to
  conversations), `message_payloads` (with the architecture §3.10 partial
  unique indexes), and `processed_events`. All primary keys are explicit
  `:uuid` columns minted in application code — no `gen_random_uuid()` — and
  timestamps are `:utc_datetime_usec`.
- Updated the Swagger UI viewer ([`contracts/openapi/index.html`](../../contracts/openapi/index.html))
  to list the Chat contract, `contracts/openapi/README.md`,
  `contracts/events/README.md`, §3.5 and §7 of the architecture document, and
  [`services/chat-service/README.md`](../../services/chat-service/README.md).
- Added an illustrated English reference for this slice:
  [`docs/development/chat-contract-slice-one.html`](../../docs/development/chat-contract-slice-one.html)
  (source) and its rendered
  [`chat-contract-slice-one.pdf`](../../docs/development/chat-contract-slice-one.pdf),
  linked from [`docs/development/README.md`](../../docs/development/README.md).
  It summarises the contract, the four event schemas, the `chat_db` model with
  ER/sequence/flow diagrams, the design decisions, verification results, and
  open risks. It is a read-only summary: on disagreement the contracts, the
  architecture document, or an ADR win.

## Why

Endpoints cannot be implemented against an undocumented surface. This slice
pins the REST shape, the stable error codes, the idempotency semantics
(device fingerprint retries, deterministic direct conversations,
`client_message_id` deduplication, forward-only read cursors), the cursor
pagination rules, and the neutral storage schema — without encoding any
still-open E2EE protocol decision: no `device_key_packages`, no
`messages.crypto_epoch`, no MLS ciphersuite columns, and no control-message
endpoints. ADR 0014 (commit authorization) is still proposed and is not
encoded.

## Verification

- `python3 scripts/contracts/validate.py --base-ref origin/main` — 5 schema(s),
  6 valid and 4 invalid event example(s); both OpenAPI files OK.
- `python3 scripts/ci/check-links.py` — relative documentation links OK.
- `python3 scripts/ci/check-changelog.py --all` — change records OK.
- `docker compose up -d postgres` — PostgreSQL 18.6 `healthy`.
- `services/chat-service`: `mix deps.get`, `mix format --check-formatted`,
  `mix compile --warnings-as-errors` — clean; `mix test` — 6 passed (the test
  alias creates and migrates `chat_db_test`, so the new migrations ran against
  a real PostgreSQL 18.6).
- `MIX_ENV=test mix ecto.rollback --all` then `MIX_ENV=test mix ecto.migrate` —
  every new migration rolled back and re-applied cleanly; the composite
  foreign keys, partial unique indexes, and CHECK constraints were verified in
  `chat_db_test` via `pg_indexes`/`pg_constraint` afterwards.
- Reference document rendered with headless Chromium from the HTML source;
  `pdfinfo` reports 13 A4 pages, `pdftotext` confirms all sections and figures
  are present, and the table of contents page numbers were checked against the
  rendered section starts.

## Follow-ups

- **Message aggregate scope:** `chat.message.created` uses
  `aggregate_type=message` with `aggregate_version=1` to avoid overloading the
  conversation version space; per-conversation ordering is carried by `seq` in
  the payload. Any future conversation-scoped event that wants
  `aggregate_type=conversation` (key rotation, membership change, tombstone)
  needs its own version counter and an ADR before implementation.
- **Outbox columns drift:** the existing `20261026000001_create_outbox_events`
  migration stores `envelope` and `event_id` while architecture §3.18
  recommends `type`/`payload`/`schema_version`/`trace_id` columns; reconcile
  the two before the Chat events context lands.
- **Validator binding:** `scripts/contracts/validate.py` proves every payload
  schema is valid JSON Schema but does not bind payload schemas to envelope
  `type` values or validate payload fixtures against them; closing that gap
  would also guard the new Chat fixtures.
- **Chat authentication is provisional** pending architecture §9.1: the
  `chatBearer` scheme name and 401/403 semantics are stable, the credential
  format is not.
- **ADR 0014 is still proposed**; this slice deliberately does not encode
  commit authorization, group key rotation, or control-message endpoints.
