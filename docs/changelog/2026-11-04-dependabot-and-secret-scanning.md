---
date: 2026-11-04
type: chore
scope: security
summary: Add Dependabot updates and gitleaks secret scanning
breaking: false
adr: -
contracts: -
---

# Add Dependabot updates and gitleaks secret scanning

## Change

- [`.github/dependabot.yml`](../../.github/dependabot.yml): weekly version
  updates on Monday at 04:00 `Africa/Cairo` for:
  - `bun` at `/` — the root `bun.lock` covers the `apps/*` and `packages/*`
    workspaces;
  - `mix` at `/services/event-broker`;
  - `mix` at `/services/chat-service`;
  - `github-actions` at `/`.
  Each ecosystem groups minor and patch updates into one pull request
  (`patterns: ["*"]`, `update-types: ["minor", "patch"]`); major updates stay
  ungrouped and open individually. Commits use the `chore(deps)` prefix.
- [`.github/workflows/security.yml`](../../.github/workflows/security.yml):
  a `gitleaks` job with `contents: read`, a per-ref concurrency group, and a
  10-minute timeout. It installs gitleaks 8.30.1 from the official release
  tarball after checking the pinned SHA-256, then:
  - on `pull_request`, scans `origin/$BASE_REF..HEAD` after fetching the base
    ref;
  - on `push` to `main` and on `workflow_dispatch`, scans the full history.
  Findings are redacted in the log (`--redact`), and any finding exits `1`.
- [`.github/workflows/governance.yml`](../../.github/workflows/governance.yml):
  the `change-records` job is skipped when `github.actor` is
  `dependabot[bot]`. The bot cannot author a change record or a `Changelog:`
  trailer, so its pull requests would otherwise always be red.
- [`docs/changelog/README.md`](README.md) and
  [`/.github/README.md`](../../.github/README.md): document the Dependabot
  exemption, the secret-scanning gate, and the new workflow row.

## Why

Issue #28. Dependency updates and secret scanning were both manual: the two
lockfiles and `bun.lock` were bumped by hand, which is how `bandit` fell behind
in chat and the broker, and no workflow scanned for committed credentials.

Two implementation choices differ from the issue text:

- **`bun`, not `npm`.** Dependabot now has a native `bun` ecosystem for the
  text `bun.lock` (Bun >= 1.1.39); the repository pins Bun 1.4.4 and has no
  `package-lock.json`. An `npm` entry at `/` would find no supported lockfile,
  and a second entry at `/apps/web` would have no lockfile either because the
  workspace is resolved from the root `bun.lock`.
- **gitleaks CLI, not `gitleaks/gitleaks-action`.** The action requires a
  `GITLEAKS_LICENSE` secret for organization-owned repositories, and
  `DevHustlers-Community` is an organization. The CLI is the same detection
  engine and rules with no license requirement; the workflow pins the version
  and verifies the release checksum.

## Verification

- Full-history scans with gitleaks 8.30.1, `--redact`:
  - all refs (`--log-opts=--all`): 47 commits, 1.11 MB, 0 findings, 335 ms;
  - `upstream/main` history: 40 commits, 1.08 MB, 0 findings, 417 ms.
- Detection test in a temporary worktree: a commit adding a fake generic API key
  was rejected by `gitleaks git . --log-opts="upstream/main..HEAD" --exit-code
  1` (rule `generic-api-key`, value redacted), exit code `1`. The worktree and
  branch were removed; the value was never a real credential.
- `.github/dependabot.yml` and `.github/workflows/security.yml` parse as YAML;
  the config has four update entries with the expected ecosystems, directories,
  and minor/patch groups.
- `python3 scripts/ci/check-links.py` and `python3
  scripts/ci/check-changelog.py --all` → pass.
- CI and the negative test: see the pull request and the change record update
  after the workflow runs.

## Follow-ups

- Dependabot only reads the configuration from the default branch, so the first
  grouped pull requests appear after merge; confirm the grouping on that run.
- Add a `GITLEAKS_LICENSE` secret and switch to `gitleaks/gitleaks-action` if
  pull request comments or SARIF upload are wanted; the CLI gate remains valid
  without it.
- Dependency review and CodeQL are separate security work, not part of this
  change.
