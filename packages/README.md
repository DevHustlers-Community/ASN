# Packages

Shared TypeScript tooling. No business domain logic lives here.

| Package | Purpose |
|---|---|
| [`api-client/`](api-client/README.md) | Generated REST clients and types |
| `config-typescript/` | Shared `tsconfig` presets |
| `config-eslint/` | Shared lint configuration |
| `config-formatting/` | Shared formatter configuration |

**Rules:**

- Packages are consumed by `apps/*` and by the Bun services.
- Generated code is never edited by hand; regenerate from `contracts/`.
- No package may import from `apps/` or `services/`.
- Versions are workspace-local during early development; publish only when a
  stable external consumer exists.
