# GitHub automation

| Path | Purpose |
|---|---|
| [`workflows/governance.yml`](workflows/governance.yml) | Validate per-commit change records and relative documentation links |
| [`workflows/contracts.yml`](workflows/contracts.yml) | Validate OpenAPI and event contracts, including breaking-change checks against the base branch |
| [`workflows/web.yml`](workflows/web.yml) | Web client: typecheck, tests, and build under Bun |
| [`workflows/broker.yml`](workflows/broker.yml) | Event broker: format, compile with warnings as errors, and tests on disposable PostgreSQL 18 |
| [`workflows/chat.yml`](workflows/chat.yml) | Chat service: format, compile with warnings as errors, and tests on disposable PostgreSQL 18 |
| [`workflows/e2e.yml`](workflows/e2e.yml) | Cross-service e2e: chat outbox → relay → broker publish → claim → ack → `/metrics`, on disposable PostgreSQL 18 |
| [`workflows/security.yml`](workflows/security.yml) | Secret scanning with gitleaks and dependency audits (`bun audit`, `mix hex.audit`): pull requests, `main`, and a weekly schedule |
| [`ISSUE_TEMPLATE/`](ISSUE_TEMPLATE/) | Bug, feature, and ADR-request forms |
| [`PULL_REQUEST_TEMPLATE.md`](PULL_REQUEST_TEMPLATE.md) | Review, contract, security, and verification checklist |
| [`CODEOWNERS`](CODEOWNERS) | Ownership by service, app, contract, and governance path |

**Governance gate (available now):**

- Every pull request commit has a valid record under
  [`docs/changelog/`](../docs/changelog/README.md).
- The `Changelog:` trailer matches a record changed by that commit.
- Filename and front-matter rules pass.
- Relative documentation links resolve.
- Pull request commits and the full history on `main` are scanned for secrets
  with gitleaks, and dependency advisories fail the build for the Bun workspace
  and both Elixir services (see
  [`workflows/security.yml`](workflows/security.yml)). A weekly scheduled run
  catches advisories disclosed without a code change.
- OpenAPI documents and event schemas are validated, and a pull request that
  removes an OpenAPI path, operation, or required field without an
  `info.version` bump fails (see [`workflows/contracts.yml`](workflows/contracts.yml)).
- Dependabot pull requests skip the per-commit record and trailer checks: the
  bot cannot author a change record. Their diffs only touch manifests and
  lockfiles, and the service workflows still run their tests.

**Service CI gates (land with the first manifests):**

- Client-generation drift check.
- TypeScript: typecheck, lint, and unit tests for apps and Bun services.
- Elixir: format, compile with warnings as errors, and tests.
- Integration tests for cross-service flows touched by the change.

**Rules:**

- Workflows never print secrets or full evidence payloads.
- A reviewed `gitleaks` false positive is ignored by exact fingerprint in
  [`.gitleaksignore`](../.gitleaksignore), with the reason written next to it.
  Do not exclude a whole file or disable a rule to silence one finding.
- Every workflow declares `permissions: contents: read`, a per-workflow
  concurrency group that cancels superseded runs, and a job timeout.
- Database-backed jobs use disposable PostgreSQL instances, one per service.
- A failing contract or change-record check blocks merge; it is not overridden by
  a code label.

**Status:** governance automation, contract validation, and the web, broker,
chat, cross-service e2e, and security workflows are written. Remaining service
workflows (Social, Moderation) land with their first manifests;
client-generation drift checks land with the contracts tooling.
