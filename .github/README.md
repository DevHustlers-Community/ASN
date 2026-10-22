# GitHub automation

| Path | Purpose |
|---|---|
| [`workflows/governance.yml`](workflows/governance.yml) | Validate per-commit change records and relative documentation links |
| [`ISSUE_TEMPLATE/`](ISSUE_TEMPLATE/) | Bug, feature, and ADR-request forms |
| [`PULL_REQUEST_TEMPLATE.md`](PULL_REQUEST_TEMPLATE.md) | Review, contract, security, and verification checklist |
| [`CODEOWNERS`](CODEOWNERS) | Ownership by service, app, contract, and governance path |

**Governance gate (available now):**

- Every pull request commit has a valid record under
  [`docs/changelog/`](../docs/changelog/README.md).
- The `Changelog:` trailer matches a record changed by that commit.
- Filename and front-matter rules pass.
- Relative documentation links resolve.

**Service CI gates (land with the first manifests):**

- Contract validation and client-generation drift check.
- TypeScript: typecheck, lint, and unit tests for apps and Bun services.
- Elixir: format, compile with warnings as errors, and tests.
- Integration tests for cross-service flows touched by the change.
- Secret scanning and dependency review.

**Rules:**

- Workflows never print secrets or full evidence payloads.
- Database-backed jobs use disposable PostgreSQL instances, one per service.
- A failing contract or change-record check blocks merge; it is not overridden by
  a code label.

**Status:** governance automation is written; service-specific workflows are not.
They land with the first scaffolded service and its manifest.
