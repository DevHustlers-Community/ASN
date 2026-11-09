---
date: 2026-11-09
type: docs
scope: docs
summary: Align architecture, glossary, and roadmap with ADR 0007 and the current project state
breaking: false
adr: 0007, 0008
contracts: contracts/openapi/chat-api.yaml
---

# Align architecture, glossary, and roadmap with ADR 0007 and the current project state

## Change

- Updated `docs/architecture/architecture-and-schema.md`:
  - §0.12 now records MLS (RFC 9420) as the selected E2EE protocol, with the
    client library gate still open and Signal/Sesame as a documented fallback.
  - `conversations.crypto_protocol` now documents `mls-1.0` for production and
    `dev-opaque-v1` for development until the library gate passes.
  - §3.8 replaces the Signal-shaped `device_prekeys` table with a narrative
    description of `device_key_packages` as defined by ADR 0007. Column types,
    keys, and indexes are left to the KeyPackage contract and migration.
  - §9 item 6 and Appendix A now describe the remaining client library decision
    instead of an unselected protocol.
  - Removed stale prekey wording from the service ownership table and the
    security conventions.
- Updated `docs/GLOSSARY.md`: MLS is the selected protocol, Signal/Sesame is the
  documented fallback, a KeyPackage entry was added, and the open-decisions list
  now names the client library gate and broker scaling instead of the settled
  protocol and broker transport.
- Updated `AGENTS.md` §10: the open decision is the E2EE client library gate;
  broker transport is no longer listed because ADR 0008 settled it.
- Updated `services/chat-service/README.md` and `CODE_MAP.md`: the `devices`
  context is implemented; KeyPackage storage is the next slice and is not
  blocked on protocol selection.
- Updated `contracts/openapi/README.md`: the pending Chat table is
  `device_key_packages`, not `device_prekeys`.
- Updated the `crypto_protocol` description in `contracts/openapi/chat-api.yaml`.
  This is a description-only change; no path, schema, or required field changed.
- Rewrote `ROADMAP.md`: devices, the e2e happy path, and metrics exposition moved
  to Done; Next now starts with the authentication ADR and the KeyPackage slice;
  the open-decisions list reflects ADR 0007 and ADR 0008.
- Rewrote `tests/README.md`: `e2e/` is the only folder that currently exists; the
  other folders and the failure-path cases are marked planned.
- Updated `services/event-broker/README.md`: metrics are exposed on `/metrics`
  and the e2e harness exists; the remaining work is failure-path coverage and
  scaling thresholds.

## Why

ADR 0007 (accepted) selects MLS and `device_key_packages`, and ADR 0008
(accepted) settles broker transport, retention, payload limits, and replay. The
architecture document, glossary, `AGENTS.md`, several service READMEs, and the
roadmap still described the protocol and broker transport as undecided, and the
roadmap still described the e2e harness and metrics as missing. Those
contradictions would mislead the next implementation slice, especially the
KeyPackage work, which must be built on the accepted ADR rather than on the old
`device_prekeys` description.

This change is documentation-only except for one OpenAPI description line. It
does not select a client library, add a migration, or claim that production
E2EE is ready.

## Verification

- `git diff --check` — clean
- `python3 scripts/ci/check-links.py` — relative documentation links OK
- `python3 scripts/contracts/validate.py --base-ref upstream/main` — both
  OpenAPI files valid; no removed path, operation, or required field
- `python3 scripts/ci/check-changelog.py --all` — change records OK
- `python3 scripts/ci/check-changelog.py --range upstream/main..HEAD` and
  `python3 scripts/ci/check-commit-trailer.py --range upstream/main..HEAD` —
  run after the commit

## Follow-ups

- The E2EE client library gate in ADR 0007 remains open; development continues
  to use `dev-opaque-v1`.
- The KeyPackage contract, `device_key_packages` migration, context, and atomic
  claim tests are the next Chat slice.
- Chat HTTP endpoints still wait on the authentication ADR (architecture §9.1).
