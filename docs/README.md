# Documentation

| Path | Contents |
|---|---|
| [`architecture/`](architecture/README.md) | System architecture, data ownership, schema |
| [`GLOSSARY.md`](GLOSSARY.md) | Domain vocabulary, field meanings, disambiguations |
| [`decisions/`](decisions/README.md) | Architecture Decision Records (ADRs) |
| [`changelog/`](changelog/README.md) | Per-commit change records and naming rules |
| [`security/`](security/README.md) | Threat model, auth, authorization, reporting |
| [`development/`](development/README.md) | Getting started, local environment, testing, conventions |
| [`operations/`](operations/README.md) | Migrations, backups, monitoring, incidents, broker recovery |

**Rules:**

- The architecture document describes the current target design; ADRs record why
  a decision was made.
- If a document and an ADR disagree, the ADR wins and the document is corrected
  in the same change.
- Every content commit has a change record under
  [`changelog/`](changelog/README.md); release notes aggregate those records.
- No stale stack assumptions. When the stack changes, every affected document is
  updated or explicitly marked superseded.
