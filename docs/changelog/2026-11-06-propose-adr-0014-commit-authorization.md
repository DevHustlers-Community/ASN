---
date: 2026-11-06
type: docs
scope: decisions
summary: Propose ADR 0014 on community commit authorization and post-block removal
breaking: false
adr: "0014"
contracts: -
---

# Propose ADR 0014 on community commit authorization and post-block removal

## Change

- Added `docs/decisions/0014-community-commit-authorization.md` (status
  `proposed`), answering the two questions ADR 0007 deferred to it:
  - who may author a membership-changing `Commit` in a community channel
    (active member plus an administrative role, checked server-side on every
    submission), and
  - who triggers the `Remove Commit` after a block or ban (Social performs the
    moderation act; the conversation's remaining administrators perform the
    rotation), including the device-list source, and the behavior when no
    authorized client is online.
- The ADR also fixes the enforcement surface ADR 0007 flagged: block/ban checks
  on KeyPackage claim/upload, conversation join, device registration, and
  send/Commit submission, all reading one chat-side state.
- Updated `docs/decisions/README.md`: 0014 recorded as proposed; status line
  now reads 0007, 0008 and 0011 accepted, 0012 and 0014 proposed.
- Linked ADR 0014 from `docs/architecture/architecture-and-schema.md` at the
  §3.5 crypto rule and open decision 9 (group key rotation), without changing
  any schema or stack statement.

## Why

ADR 0007 (accepted) names ADR 0014 as the owner of commit authorization and the
block/ban Remove Commit workflow, and these gate protocol-specific chat schema
work (`device_key_packages`, `messages.crypto_epoch`). Writing the decision as
a document first keeps the contract-first order and avoids inventing
authorization behavior in code.

## Verification

- `python3 scripts/ci/check-links.py` — pending.
- `python3 scripts/ci/check-changelog.py --all` — pending.

No code, migrations, OpenAPI contracts, or event schemas were changed, so no
service test suite was run.

## Follow-ups

- Accept ADR 0014 after review; only then does it bind implementation.
- Protocol-neutral chat slice (contracts, event schemas, neutral `chat_db`
  migrations) remains the next implementation step.
- Architecture §0.12 and §9.6 still say the cryptographic protocol is not
  selected; they conflict with accepted ADR 0007 and need their own docs change.
