---
date: 2026-11-06
type: docs
scope: decisions
summary: Accept ADR 0007 selecting MLS (RFC 9420) as the E2EE protocol
breaking: false
adr: "0007"
contracts: -
---

# Accept ADR 0007 selecting MLS (RFC 9420) as the E2EE protocol

## Change

- Changed `docs/decisions/0007-e2ee-protocol-selection.md` status from
  `proposed` to `accepted`. The decision text is unchanged: MLS (RFC 9420)
  for direct and community conversations, Chat as the MLS Delivery Service,
  per-device leaves, and opaque-only server storage.
- Updated `docs/decisions/README.md`: 0007 now shows `accepted`; summary line
  reads 0007, 0008 and 0011 are accepted (0012 remains proposed).

## Why

The owner confirmed we will rely on E2EE (MLS). Accepting the ADR unblocks
protocol-neutral chat design and preserves the recorded limits: the client
library gate, the classic-ciphersuite v1 baseline (hybrid PQ deferred),
and the open items in ADR 0007 continue to apply. No protocol or client
library is selected beyond what ADR 0007 records.

## Verification

- `python3 scripts/ci/check-links.py` — passed.
- `python3 scripts/ci/check-changelog.py --all` — passed.

No code, migrations, OpenAPI contracts, or event schemas were changed, so no
service test suite was run.

## Follow-ups

- ADR 0014 must define who may send Commits in community channels and who
  triggers the Remove Commit after a block or ban (ADR 0007 open question).
- The client-library gate remains open; no library is selected by this change.
- Open decisions 8, 9, 10, and 13 still need their own records.
