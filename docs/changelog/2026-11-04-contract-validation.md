---
date: 2026-11-04
type: ci
scope: contracts
summary: Validate OpenAPI and event contracts, including breaking-change detection
breaking: false
adr: -
contracts: contracts/openapi/event-broker-api.yaml, contracts/events/common/event-envelope.schema.json
---

# Validate OpenAPI and event contracts

## Change

- [`scripts/contracts/validate.py`](../../scripts/contracts/validate.py): one
  entry point that validates every OpenAPI document, resolves internal and
  external `$ref`s, checks the broker `EventEnvelope` against the shared
  envelope schema, validates every event schema and envelope example, and
  rejects a removed OpenAPI path, operation, or required field without an
  `info.version` bump.
- [`scripts/contracts/requirements.txt`](../../scripts/contracts/requirements.txt):
  pin `openapi-spec-validator`, `jsonschema`, and `PyYAML`.
- [`scripts/contracts/README.md`](../../scripts/contracts/README.md): setup and
  the list of checks.
- [`contracts/events/examples/`](../../contracts/events/examples/README.md): two
  valid and four invalid envelope fixtures. `valid-*.json` must pass; any other
  prefix is an error.
- [`.github/workflows/contracts.yml`](../../.github/workflows/contracts.yml):
  run the validator on changes under `contracts/` or `scripts/contracts/`,
  passing the pull request base ref for the breaking-change check.
- `contracts/`, `README.md`, `AGENTS.md`, `scripts/README.md`, and
  `.github/README.md`: record that contract validation exists and that client
  generation is still pending.

## Why

Issue #29. Nothing validated `contracts/openapi/event-broker-api.yaml` or
`contracts/events/common/event-envelope.schema.json`, and no workflow referenced
`contracts/`. A broken `$ref`, an envelope fixture that violates the schema, or
a removed required field could merge without a signal.

The version check is deliberately narrow: additive changes keep `info.version`;
only removed paths, operations, and required fields fail. That matches
[`contracts/VERSIONING.md`](../../contracts/VERSIONING.md) without forcing a bump
for every compatible addition.

## Verification

- `python3 scripts/contracts/validate.py`: pass on `main` (1 OpenAPI document,
  1 JSON Schema, 2 valid and 4 invalid examples).
- Missing internal `$ref` (`#/components/schemas/MissingEnvelope`): exit 1.
- Missing external `$ref` (`missing.schema.json`): exit 1.
- A `valid-*.json` fixture with no `payload`: exit 1.
- Removing `ClaimResponse.required` without a version bump: exit 1, naming the
  removed required field.
- The same removal with `info.version` `1.0.0` -> `1.0.1`: pass.
- `contracts.yml` parses as YAML.
- `check-links.py` and `check-changelog.py --all`: pass.

## Follow-ups

- Client and type generation, and its drift check, remain unimplemented.
- Per-event payload schemas land with their producers; the validator will pick
  them up from `contracts/events/**/*.schema.json` automatically.
