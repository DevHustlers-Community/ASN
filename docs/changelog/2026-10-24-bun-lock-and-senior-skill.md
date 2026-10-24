---
date: 2026-10-24
type: chore
scope: web
summary: Adopt bun.lock and add asn-senior-frontend skill with guardrails and effort matrix
breaking: false
adr: -
contracts: -
---

# Adopt bun.lock and add asn-senior-frontend skill

## Change

- Removed `package-lock.json` and generated `bun.lock` via `bun install`.
- Added `.agents/skills/asn-senior-frontend/SKILL.md` defining negative constraints,
  Bun-native workflows, RTL-first tokens, and a Reasoning Effort Calibration Matrix (Low vs Medium vs Max).

## Why

The ASN architecture specifies Bun as the primary JavaScript/TypeScript runtime across the monorepo.
Transitioning to Bun's native `bun.lock` prevents package manager divergence and CI lockfile conflicts.
The senior frontend skill equips implementing AI agents (such as ZCode) with strict negative guardrails
(preventing plaintext chat, unapproved dependencies, and direct git commits) while guiding model reasoning
effort calibration to optimize quality across the token budget.

## Verification

- `bun install`: Generated `bun.lock` cleanly in 2.61s.
- `bun run build:web`: Production bundle compiled in 893ms with 0 errors.
- `node A:\glm\ZCode\resources\glm\zcode.cjs skills list`: Confirmed `asn-senior-frontend` is registered.
- `py scripts/ci/check-changelog.py --all`: Passed.
- `py scripts/ci/check-links.py`: Passed.
