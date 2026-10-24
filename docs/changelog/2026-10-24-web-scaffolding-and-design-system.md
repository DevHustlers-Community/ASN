---
date: 2026-10-24
type: feat
scope: web
summary: Scaffold web client application and document frontend design system
breaking: false
adr: 0012
contracts: -
---

# Scaffold web client application and document frontend design system

## Change

- Initialized root monorepo workspace configuration in `package.json`.
- Added `@asn/config-typescript` shared presets (`base.json` and `react.json`).
- Scaffolded public web client in `apps/web/` using React 18, Vite 5, TypeScript 5, and Tailwind CSS.
- Downloaded and embedded local offline fonts (`IBM Plex Sans Arabic` and `JetBrains Mono`) with `@font-face` definitions; zero external CDN dependencies.
- Integrated the initial ASN brand logo assets and updated application headers and favicon.
- Authored the comprehensive design system specification in `docs/architecture/design-system.md` covering the token-driven multi-theme engine, 4px spacing grid, WCAG 2.1 AA accessibility (Triple-Signal rule), adaptive media grid, and 4px consecutive chat grouping.
- Added structured `README.md` documentation for all feature and utility directories under `apps/web/src/`.

## Why

The ASN web client had only placeholder documentation and no runnable scaffolding or local fonts. This change establishes the frontend architecture, design tokens, and modular feature layout, enabling rapid feature development while ensuring offline reliability and strict visual consistency.

## Verification

- `bun install` succeeded cleanly.
- `bun run build:web` (`tsc && vite build`) passed with zero type or bundling errors.
- `python3 scripts/ci/check-changelog.py --all`
- `python3 scripts/ci/check-links.py`

## Follow-ups

- Implement first API client generated types from `contracts/openapi/`.
- Build and connect Phoenix Channels WebSocket client in `src/lib/websocket/`.
