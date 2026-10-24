---
date: 2026-10-24
type: chore
scope: web
summary: Adopt bun.lock and standardize on Bun lockfile
breaking: false
adr: -
contracts: -
---

# Adopt bun.lock and standardize on Bun lockfile

## Change

- Removed `package-lock.json` and generated `bun.lock` via `bun install`.

## Why

The ASN architecture specifies Bun as the primary JavaScript/TypeScript runtime across the monorepo.
Transitioning to Bun's native `bun.lock` prevents package manager divergence and CI lockfile conflicts.

## Verification

- `bun install`: Generated `bun.lock` cleanly.
- `bun run build:web`: Production bundle compiled with 0 errors.
- `python3 scripts/ci/check-changelog.py --all`: Passed.
- `python3 scripts/ci/check-links.py`: Passed.
