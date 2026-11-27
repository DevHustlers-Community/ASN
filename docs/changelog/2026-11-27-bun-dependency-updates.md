---
date: 2026-11-27
type: chore
scope: deps
summary: Reapply Bun dependency updates in a governance-compliant commit
breaking: false
adr: -
contracts: -
---

# Reapply Bun dependency updates

## Change

- Reapplied the Bun dependency updates originally authored by Dependabot for
  `@tanstack/react-query`, `lucide-react`, `zustand`, Tailwind PostCSS, the Vite
  React plugin, and Tailwind/Vite.
- Preserved the resolved `bun.lock` changes in a normal commit with a change
  record and `Changelog:` trailer.

## Why

The original bot commit lacked the change record and trailer required by the
repository's per-commit governance checks. Reapplying the same dependency diff
in a compliant commit keeps the update without weakening governance policy.

## Verification

- `bun install --frozen-lockfile` — no changes.
- `bun run typecheck` — passed.
- `bun run test` — 10 passed.
- `bun run build:web` — passed.
- `bun audit` — no vulnerabilities found.
