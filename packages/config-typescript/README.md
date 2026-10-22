# @asn/config-typescript

Shared TypeScript configuration presets.

- `base.json` - strict baseline for every TypeScript package.
- `react.json` - web and admin apps.
- `react-native.json` - mobile app.
- `bun.json` - Bun services.

Enable `strict`, `noUncheckedIndexedAccess`, and `exactOptionalPropertyTypes`
unless a package documents an exception. Path aliases are package-local; no
cross-package source imports.

**Status:** not written yet; created with the first TypeScript package.
