---
date: 2026-11-04
type: ci
scope: security
summary: Fail CI when bun audit or mix hex.audit reports a dependency advisory
breaking: false
adr: -
contracts: -
---

# Fail CI when a dependency audit reports an advisory

## Change

- [`scripts/ci/check-audits.py`](../../scripts/ci/check-audits.py): parse
  `bun audit --json` and `mix hex.audit` output and exit non-zero when an
  advisory is present. Unknown output fails closed instead of passing.
- [`.github/workflows/security.yml`](../../.github/workflows/security.yml): add
  a `bun-audit` job and a two-service `hex-audit` matrix, and run the workflow
  weekly so a newly disclosed advisory fails without a code change.
- [`.github/README.md`](../../.github/README.md) and
  [`scripts/README.md`](../../scripts/README.md): document the gate and the
  script.

## Why

Neither tool could be trusted to fail the build:

- `mix hex.audit` prints `Found packages with security advisories` and still
  exits 0. That is how EEF-CVE-2026-118391 on Ecto 3.14.2 reached `main` before
  #58.
- Bun changed its exit status across releases. `bun audit --json` currently
  exits 1 for findings on 1.4.4, but the issue evidence and older releases show
  a 0 exit with advisories printed.

Issue #23. The workflow has no `continue-on-error` and no allowlist: a finding
must be fixed or explicitly handled in a follow-up change.

## Verification

- `python3 scripts/ci/check-audits.py bun`: pass (`bun audit: no advisories`).
- `python3 scripts/ci/check-audits.py hex services/event-broker services/chat-service`:
  pass on both services.
- Negative test with a fake `mix` that prints advisories and exits 0: script
  exits 1 and reports `advisories found`.
- Negative test in a scratch workspace pinning `lodash@4.17.20`: script exits 1
  and names all four advisories, including both HIGH ones.
- `security.yml` parses as YAML.
- `check-links.py` and `check-changelog.py --all`: pass.

## Follow-ups

- No allowlist is defined; if one becomes necessary, keep it in the script so
  suppressed findings stay visible and expire.
