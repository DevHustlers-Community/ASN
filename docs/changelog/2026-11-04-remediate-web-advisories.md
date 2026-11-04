---
date: 2026-11-04
type: fix
scope: web
summary: Remediate 16 security advisories in the web dependency tree
breaking: false
adr: -
contracts: -
---

# Remediate 16 security advisories in the web dependency tree

## Change

- [`apps/web/package.json`](../../apps/web/package.json):
  - Updated `happy-dom` from `^15.11.7` to `^21.0.4`.
  - Updated `vite` from `^5.4.9` to `^7.3.7`.
  - Updated `@vitejs/plugin-react` from `^4.3.3` to `^5.1.4`.
  - Updated `react-router-dom` from `^6.27.0` to `^7.18.5`.
- [`bun.lock`](../../bun.lock): regenerated via `bun install` to record resolved safe dependency versions.

## Why

Issue #22. `bun audit` at the repository root reported 16 vulnerabilities (1 critical, 4 high, 10 moderate, 1 low) across `happy-dom`, `vite`, `esbuild`, and `react-router`:
- `happy-dom`: VM context escape leading to RCE (GHSA-37j7-fg3j-429f, critical), page-origin cookie confusion in fetch (high), unescaped export names in ECMAScriptModuleCompiler (high), SSRF via iframe/stylesheet (high), and cookie scope forgery (moderate).
- `vite` & `esbuild`: `launch-editor` Windows vulnerabilities including `fs.existsSync()` check bypass (high), NTLMv2 hash disclosure (moderate), command argument escaping omission (moderate), and dev server request reading (moderate).
- `react-router`: open redirect via backslash (moderate) and constructor injection in SSR hydration error deserialization (moderate).

## Verification

- `bun audit`: 0 vulnerabilities reported (246 packages scanned).
- `bun install --frozen-lockfile`: succeeded with 0 changes.
- `bun run typecheck`: clean pass with 0 errors.
- `bun run test`: all 10 tests across 2 suites passed.
- `bun run build:web`: production build completed cleanly with Vite 7.
- `py scripts/ci/check-changelog.py --all`: validation passed.
