---
date: 2026-10-22
type: chore
scope: governance
summary: Add governance templates, per-commit change records, and contract versioning
breaking: false
adr: -
contracts: contracts/VERSIONING.md
---

# Add governance templates, per-commit change records, and contract versioning

## Change

- Added `.github/CODEOWNERS`, issue forms, a pull request template, and a
  governance workflow.
- Added the change-record process in `docs/changelog/`, a per-change template,
  and a release-level `CHANGELOG.md`.
- Added local `pre-commit` and `commit-msg` hooks plus CI validation scripts.
- Added `contracts/VERSIONING.md` for REST and event contract versioning and
  deprecation.
- Updated `CONTRIBUTING.md`, `AGENTS.md`, and repository indexes to require and
  describe change records.

## Why

The repository had coordination artifacts documented as "planned" but not
present, no per-commit history beyond Git messages, and no written contract
versioning policy. This change makes ownership reviewable, makes every commit
carry its own rationale and verification, and gives contract changes a documented
compatibility and deprecation path.

## Verification

- `python3 scripts/ci/check-changelog.py --all`
- `python3 scripts/ci/check-links.py`
- YAML syntax check for `.github/ISSUE_TEMPLATE/*.yml` and
  `.github/workflows/governance.yml`
- No application test, typecheck, lint, or migration command exists yet, so none
  were run.

## Follow-ups

- Install the hooks in each clone with `bash scripts/dev/install-git-hooks.sh`.
- Replace the single CODEOWNERS handle with service teams when maintainers are
  added.
- Add service-specific CI once the first manifests and `mix.exs` exist.
