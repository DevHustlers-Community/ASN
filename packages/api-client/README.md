# API client

Generated TypeScript client and types for the REST contracts.

**Generated from:** [`contracts/openapi/`](../../contracts/openapi/README.md)
using the chosen generator (recorded in an ADR).

**Rules:**

- Never hand-edit generated files; CI fails on generation drift.
- The package exports types and a thin transport wrapper only. Business rules,
  caching policy, and authorization decisions stay in the app or service.
- The Chat envelope type is `Uint8Array`/`bytea`-compatible. It must never gain a
  plaintext `body` field.
- Regeneration is part of the contract change workflow, not a separate release.

**Status:** not generated yet. The first OpenAPI contracts have landed; generation
waits for the generator choice recorded in an ADR and the CI drift check.
