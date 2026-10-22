# @asn/config-eslint

Shared ESLint flat configuration.

- One base config, plus presets for React, React Native, and Bun services.
- Rules that encode architecture boundaries (no imports from `apps/` or
  `services/` into `packages/`, no cross-service imports).
- Formatting rules live in the formatter config, not here.

**Status:** not written yet; created with the first TypeScript package.
