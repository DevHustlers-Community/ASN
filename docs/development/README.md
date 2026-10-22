# Development

| Document | Purpose |
|---|---|
| [`getting-started.md`](getting-started.md) | First run: prerequisites, PostgreSQL, Chat, broker |
| [`local-environment.md`](local-environment.md) | Databases, roles, ports, env vars, compose lifecycle |
| [`elixir-services.md`](elixir-services.md) | Shared Elixir/OTP, Phoenix, Ecto, and config conventions |
| [`testing.md`](testing.md) | Test layers, database isolation, commands, failure paths |
| `coding-conventions.md` | Planned: cross-language naming and review conventions |

**Single source of truth:** commands and ports documented here must match
`compose.yaml`, `.env.example`, and each service README. Update all of them in the
same change.

**Status:** getting started, local environment, Elixir service conventions, and
testing are written for the current scaffolds. `coding-conventions.md` lands when
the first TypeScript manifest does.
