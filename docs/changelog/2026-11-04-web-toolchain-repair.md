---
date: 2026-11-04
type: fix
scope: web
summary: Repair the web toolchain after the TypeScript, Tailwind, and Vite majors
breaking: false
adr: -
contracts: -
---

# Repair the web toolchain after the TypeScript, Tailwind, and Vite majors

## Change

- [`apps/web/tsconfig.json`](../../apps/web/tsconfig.json): remove `baseUrl`,
  which TypeScript 7 no longer accepts. The `paths` mapping still resolves
  `@/*` relative to the tsconfig.
- [`apps/web/src/vite-env.d.ts`](../../apps/web/src/vite-env.d.ts): reference
  `vite/client` so the side-effect CSS import in `src/main.tsx` is typed under
  TypeScript 7.
- [`apps/web/package.json`](../../apps/web/package.json): add
  `@tailwindcss/postcss` 4.3.3 and raise `vite` to `^8.3.5`, the peer range
  required by `@vitejs/plugin-react` 6.1.2.
- [`apps/web/postcss.config.js`](../../apps/web/postcss.config.js): load
  `@tailwindcss/postcss` instead of `tailwindcss`.
- [`apps/web/src/styles/globals.css`](../../apps/web/src/styles/globals.css):
  replace the three `@tailwind` directives with `@import "tailwindcss"` and
  load the existing theme through `@config "../../tailwind.config.ts"`.
- [`apps/web/README.md`](../../apps/web/README.md): record the React 19,
  TypeScript 7, Vite 8, and Tailwind CSS 4 toolchain and the two migration
  bridges above.

## Why

The dependency majors merged into `main` changed requirements that the web
scaffold had not migrated yet:

- #54 moved TypeScript to 7.0.2, which removed `baseUrl`; the first Web run
  after the merge failed at `tsc` with
  `tsconfig.json(4,5): error TS5102: Option 'baseUrl' has been removed`
  (run 41864696174).
- TypeScript 7 also reports `TS2882` for the side-effect CSS import because
  Vite's client types were not referenced anywhere.
- #55 moved Tailwind CSS to 4.3.3, which moved the PostCSS plugin to
  `@tailwindcss/postcss` and replaced the `@tailwind` directives with a single
  `@import "tailwindcss"`. The existing JS theme remains supported through
  `@config`.
- #52 moved `@vitejs/plugin-react` to 6.1.2, whose peer range is
  `vite: ^8.0.0`; `main` had Vite 7.3.7.

## Verification

- `bun install --frozen-lockfile`: no changes.
- `bun run typecheck`: pass.
- `bun run test`: 10 pass, 0 fail, 16 expectations.
- `bun run build:web`: Vite 8.3.5, 77 modules, CSS 25.39 kB, JS 292.20 kB.
- `bun audit`: 0 vulnerabilities (175 packages).
- Generated CSS contains the custom theme utilities (`bg-base`,
  `text-text-main`, `border-border`, `rounded-card`).
- The failing run before the change: Web 41864696174 on `main` at `3c6f25f`,
  `tsconfig.json(4,5): error TS5102: Option 'baseUrl' has been removed`.

## Follow-ups

- #23 still needs Ecto 3.14.3 in both Elixir services before the audit gate can
  be strict: `mix hex.audit` reports `EEF-CVE-2026-118391` (HIGH) on Ecto
  3.14.2.
- #22 can close when this lands: `bun audit` is 0 and the typecheck, test, and
  build gates pass on the resolved tree.
