---
date: 2026-11-06
type: fix
scope: contracts
summary: Keep the base-ref YAML comparison permissive so a historical duplicate cannot block later PRs
breaking: false
adr: -
contracts: scripts/contracts/validate.py
---

# Keep the base-ref YAML comparison permissive

## Change

- `scripts/contracts/validate.py` parses the base revision with the default
  safe loader again, while still parsing every current contract with the strict
  loader that rejects duplicate keys.
- When the current file has a duplicate, the version-bump comparison skips it
  instead of raising, because `validate_openapi` already reported it.

## Why

Applying the strict loader to the base revision broke the contracts workflow on
PR #69: `main` already contained the duplicate `422` that this branch removes,
so every later pull request touching the file failed with
`cannot compare the base version: duplicate key '422'`. Strictness belongs to
the content being merged; history is compared as it was actually rendered.

## Verification

- `python3 scripts/contracts/validate.py --base-ref upstream/main` — passes even
  though `upstream/main`'s `chat-api.yaml` still carries seven `422` keys.
- Regression check: injected a duplicate `'422'` into the working tree; the
  validator fails with one clean error line and exit 1, with no traceback.
  Restored the file; the validator passes again.
- `python3 scripts/ci/check-links.py` — OK.
- `python3 scripts/ci/check-changelog.py --all` — OK.
