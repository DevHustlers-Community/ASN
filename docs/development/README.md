# Development

| Document | Purpose |
|---|---|
| [`getting-started.md`](getting-started.md) | First run: prerequisites, PostgreSQL, Chat, broker |
| [`local-environment.md`](local-environment.md) | Databases, roles, ports, env vars, compose lifecycle |
| [`elixir-services.md`](elixir-services.md) | Shared Elixir/OTP, Phoenix, Ecto, and config conventions |
| [`testing.md`](testing.md) | Test layers, database isolation, commands, failure paths |
| [`chat-contract-slice-one.html`](chat-contract-slice-one.html) · [`chat-contract-slice-one.pdf`](chat-contract-slice-one.pdf) | Illustrated English reference for the Chat contract slice one (REST, events, `chat_db` model) |
| `coding-conventions.md` | Planned: cross-language naming and review conventions |

**Single source of truth:** commands and ports documented here must match
`compose.yaml`, `.env.example`, and each service README. Update all of them in the
same change.

**Status:** getting started, local environment, Elixir service conventions, and
testing are written for the current scaffolds. `coding-conventions.md` lands when
the first TypeScript manifest does.

**Generated reference documents:** `chat-contract-slice-one.pdf` is rendered from
`chat-contract-slice-one.html` (headless Chromium, A4). The HTML is the source;
when `contracts/openapi/chat-api.yaml`, `contracts/events/chat/`, or the
architecture document changes, edit the HTML and re-render — the PDF is a
read-only summary and never the source of truth.
