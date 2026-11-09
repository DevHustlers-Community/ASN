---
date: 2026-11-09
type: fix
scope: contracts
summary: Bind event payload schemas to envelope types and validate example payloads
breaking: false
adr: -
contracts: contracts/events/*, scripts/contracts/validate.py
---

# Bind event payload schemas to envelope types and validate example payloads

## Change

- [`scripts/contracts/validate.py`](../../scripts/contracts/validate.py) now
  discovers payload schemas by name, requires
  `<event-type>.v<version>.schema.json`, and verifies each schema's `$id` equals
  its path relative to `contracts/events/`.
- Every `valid-*.json` example whose envelope is valid has its `payload`
  validated against the schema selected by the example's `type` and
  `schema_version`. A type in a namespace that already has payload schemas
  (currently `chat`) without a matching schema is an error.
- The summary line now reports the number of payload bindings.
- Updated [`contracts/events/README.md`](../../contracts/events/README.md),
  [`contracts/events/examples/README.md`](../../contracts/events/examples/README.md),
  [`scripts/contracts/README.md`](../../scripts/contracts/README.md), and
  [`contracts/README.md`](../../contracts/README.md) to describe the binding
  instead of the previous "not yet machine-bound" gap.

## Why

The first Chat contract slice added four payload schemas and four valid
fixtures, but the validator only proved that each schema was valid JSON Schema
and that each fixture satisfied the envelope. A fixture could carry a `payload`
that violated its own schema, and an event-type typo silently skipped the check.
That left the contract unable to catch payload drift before producers land.

## Verification

- `/tmp/opencode/contracts-venv/bin/python scripts/contracts/validate.py --base-ref origin/main`
  — both OpenAPI files OK; 5 schemas; 6 valid and 4 invalid examples; 4 payload
  bindings; exit 0.
- Negative payload check: added an unexpected `payload.device_label` to
  `valid-chat-device-registered.json` — the validator exited 1 with
  `Additional properties are not allowed ('device_label' was unexpected)`.
- Negative type check: changed `valid-chat-message-created.json` to
  `chat.message.creatd` — the validator exited 1 with
  `no payload schema for chat.message.creatd version 1`.
- Restored both fixtures; `git diff` shows only intended changes.
- `python3 scripts/ci/check-links.py` — OK.
- `python3 scripts/ci/check-changelog.py --all` — OK.

## Follow-ups

- Client generation and drift checks remain unimplemented
  ([`packages/api-client`](../../packages/api-client/README.md)).
- The outbox columns still differ from architecture §3.18; reconcile them before
  the Chat events context lands.
