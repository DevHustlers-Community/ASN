---
date: 2026-11-09
type: docs
scope: docs
summary: Correct stale references left by the Chat contract slice and gitleaks fix
breaking: false
adr: -
contracts: -
---

# Correct stale references left by the Chat contract slice and gitleaks fix

## Change

- [`.gitleaksignore`](../../.gitleaksignore) now names the changelog record that
  actually exists (`2026-11-06-gitleaks-device-fingerprint-false-positive.md`)
  instead of `2026-11-06-chat-device-fingerprint-fixture`.
- [`services/chat-service/README.md`](../../services/chat-service/README.md)
  marks ADR 0009 as planned; it is listed under "Planned ADRs" and is not
  recorded.
- [`contracts/openapi/README.md`](../../contracts/openapi/README.md) no longer
  says no business-service contract is written while `chat-api.yaml` is
  present; it names Social and Moderation as the outstanding contracts.
- [`packages/api-client/README.md`](../../packages/api-client/README.md) no
  longer says generation is blocked on the first OpenAPI files; those files
  have landed, and the remaining blocker is the generator ADR plus the drift
  check.
- [`ROADMAP.md`](../../ROADMAP.md) no longer claims the Chat
  accounts/conversations/messages contexts exist; only the scaffold, contract
  slice, outbox, and relay are done.

## Why

A re-inspection of the last three commits found documentation that contradicted
the tree. Stale references cost reviewers time and hide real blockers (the
generator ADR) behind already-resolved ones (missing OpenAPI files).

## Verification

- `python3 scripts/ci/check-links.py` — OK.
- `python3 scripts/ci/check-changelog.py --all` — OK.
- `rg` for the old strings — no matches remain.
- `gitleaks` is not installed in this environment, so the ignore-file comment
  was checked against `docs/changelog/` by filename. The full-history scan
  remains covered by the Security workflow.
