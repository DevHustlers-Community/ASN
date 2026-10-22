# Development

| Document | Purpose |
|---|---|
| `getting-started.md` | First run: prerequisites, install, local stack |
| `local-environment.md` | Databases, ports, env vars, seeded data |
| `testing.md` | Test layers, commands, fixtures, failure-path tests |
| `coding-conventions.md` | Language and repository conventions |

**Single source of truth:** commands and ports documented here must match
`compose.yaml`, `.env.example`, and each service README. Update all of them in the
same change.

**Status:** not written yet. `getting-started.md` lands with the first runnable
service.
