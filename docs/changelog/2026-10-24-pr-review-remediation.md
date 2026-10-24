---
date: 2026-10-24
type: fix
scope: web
summary: Address PR review comments, standardize on Bun, and add ADR 0012
breaking: false
adr: 0012
contracts: -
---

# Address PR review comments, standardize on Bun, and add ADR 0012

## Change

- Standardized the frontend toolchain on Bun (`packageManager: bun@1.4.4`, `workspace:*`, Bun workspace filter scripts, and GitHub Actions CI workflow).
- Resolved product naming to ASN per `docs/GLOSSARY.md` across UI, HTML metadata, and documentation.
- Formulated ADR 0012 (`docs/decisions/0012-frontend-design-system-and-theming.md`) and marked `docs/architecture/design-system.md` as Proposed target specification.
- Updated tokens to RGB triplets to enable Tailwind alpha utilities (`bg-primary/10`, `border-status-success/30`).
- Fixed accessibility contrast (WCAG 2.1 AA) with `--primary-foreground`, `#9ca3af` text-dim, 12px font floor, and aria attributes.
- Added Bun component tests (`happy-dom`) covering `cn`, Button variants, Badge tints, and theme switching.
- Updated source-of-truth documentation (`AGENTS.md`, `getting-started.md`, `local-environment.md`, `testing.md`).

## Why

Addresses review feedback on PR #1 from upstream maintainers to eliminate toolchain split,
resolve implicit naming/E2EE decisions, enforce WCAG AA accessibility, and guarantee reproducible CI runs.

## Verification

- `bun install --frozen-lockfile`: Passed.
- `bun run typecheck`: Passed (exit 0).
- `bun run lint`: Passed (exit 0).
- `bun run test`: Passed (10 tests in 83ms).
- `bun run build:web`: Passed (Vite build in 900ms).
- `python3 scripts/ci/check-changelog.py --all`: Passed.
- `python3 scripts/ci/check-links.py`: Passed.
