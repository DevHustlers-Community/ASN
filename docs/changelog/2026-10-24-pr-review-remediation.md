---
date: 2026-10-24
type: fix
scope: web
summary: Address PR review comments, align design system tokens, and enforce WCAG AA
breaking: false
adr: 0012
contracts: -
---

# Address PR review comments, align design system tokens, and enforce WCAG AA

## Change

- Standardized the frontend toolchain on Bun (`packageManager: bun@1.4.4`, `workspace:*`, Bun scripts, and GitHub Actions CI workflow).
- Resolved product naming strictly to ASN per `docs/GLOSSARY.md` across UI, HTML metadata, and documentation; replaced provisional logo with square ASN icons (32x32, 180x180, 512x512).
- Restored accidentally truncated sections in `docs/development/local-environment.md` and `docs/development/testing.md`, and restored ADR index in `docs/decisions/README.md`.
- Formulated ADR 0012 (`docs/decisions/0012-frontend-design-system-and-theming.md`) and re-encoded `docs/architecture/design-system.md` as UTF-8 without BOM, removing mojibake and aligning tokens with `tokens.css`.
- Enforced WCAG 2.1 AA accessibility (>= 4.5:1 text contrast across dark, dim, and light modes; >= 3.0:1 focus rings) via per-theme semantic status foreground tokens and `--primary-text`.
- Added visible indicator (checkmark) for active accent selection and explicit visible presence indicator in author metadata.
- Cleaned `apps/web/README.md` (marked E2EE as planned, corrected state management note, aligned style sheet path to `globals.css`).
- Cleaned redundant lint script in favor of standard `typecheck` and documented follow-up.
- Added component unit tests with Bun test and happy-dom.

## Why

Addresses maintainer review feedback on PR #1 from upstream repository to eliminate toolchain drift,
restore architectural documentation, ensure true WCAG 2.1 AA accessibility, and align tokens with the source of truth.

## Verification

- `bun install --frozen-lockfile`: Passed.
- `bun run typecheck`: Passed (exit 0).
- `bun run test`: Passed (10 tests, 16 expect calls in 4.38s).
- `bun run build:web`: Passed (Vite production build in 22.8s).
- `python3 scripts/ci/check-changelog.py --all`: Passed.
- `python3 scripts/ci/check-links.py`: Passed.
