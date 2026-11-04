---
date: 2026-11-04
type: chore
scope: ci
summary: Add permissions, concurrency, timeouts, and Bun caching to the remaining workflows
breaking: false
adr: -
contracts: -
---

# Add permissions, concurrency, timeouts, and Bun caching

## Change

- [`.github/workflows/web.yml`](../../.github/workflows/web.yml): declare
  `permissions: contents: read`, a `web` concurrency group, a 15-minute job
  timeout, and cache Bun's install cache keyed on `bun.lock`.
- [`.github/workflows/broker.yml`](../../.github/workflows/broker.yml): declare
  the same permissions and a `broker` concurrency group, and a 15-minute job
  timeout. The existing `deps`/`_build` cache is unchanged.
- [`.github/workflows/governance.yml`](../../.github/workflows/governance.yml):
  add a 5-minute job timeout.
- [`.github/README.md`](../../.github/README.md): record the workflow rules.

## Why

Issue #27. `broker.yml` and `web.yml` had no least-privilege `permissions` and
no concurrency group, so two pushes to the same branch ran twice. No workflow
set a job timeout, so a hung job could run for GitHub's 360-minute default.
`web.yml` also reinstalled Bun dependencies on every run with no cache.

Chat, E2E, and Security already followed the target shape; this change brings
the remaining three workflows in line.

## Verification

- `grep -nE "^permissions:|^concurrency:|timeout-minutes:|actions/cache"`
  shows all six workflows declare the expected settings.
- `web.yml`, `broker.yml`, and `governance.yml` parse as YAML.
- A second Web run on the pull request restores the Bun cache (see the workflow
  log).
- `check-links.py` and `check-changelog.py --all`: pass.
