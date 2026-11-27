---
date: 2026-11-27
type: docs
scope: docs
summary: Synchronize project status and service maps with implemented slices
breaking: false
adr: -
contracts: -
---

# Synchronize current implementation status

## Change

- Updated the root README to distinguish implemented Chat device/KeyPackage APIs
  from contract-only conversations and messages.
- Updated ROADMAP completed items for Broker remediation and E2E hardening.
- Corrected Chat's Bandit version and clarified that projection consumers are
  planned rather than implemented.
- Kept service documentation aligned with the current broker and Chat code maps.

## Why

The previous status text predated authenticated Chat device endpoints and the
Broker security/correctness work, and overstated event-consumer implementation.

## Verification

- `python3 scripts/ci/check-changelog.py --all` — change records OK.
- `python3 scripts/ci/check-links.py` — relative documentation links OK.
- `git diff --check` — clean.
