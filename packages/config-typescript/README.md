# @asn/config-typescript

Shared TypeScript configuration presets for the ASN monorepo.

## Available Presets

- `base.json` — Strict baseline for every TypeScript package (`strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`).
- `react.json` — Configuration for React web applications (used by `apps/web`), with JSX preserve/react-jsx and DOM libraries.
- `bun.json` — Configuration preset for Bun-based services and scripts with Bun types.

## Planned Presets

- `react-native.json` — Configuration preset for the mobile application.

## Conventions

Path aliases remain package-local (for example, `@/*` mapping to `./src/*` within `apps/web`). There are no cross-package source imports without explicit workspace package dependencies.

**Status:** `base.json`, `react.json`, and `bun.json` are implemented and active. `react-native.json` is planned.
