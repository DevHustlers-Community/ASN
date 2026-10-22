# Web app

Public-facing React + TypeScript client.

**Owns:** browser UI state and non-sensitive client cache only.

**Planned layout (`src/`):**

| Path | Purpose |
|---|---|
| `app/` | Routing, providers, layouts |
| `features/` | One folder per product area: auth, feed, posts, comments, reactions, profiles, relationships, communities, search, hashtags, notifications, chat, settings |
| `components/ui/` | Reusable web-only UI primitives |
| `lib/api/` | REST client wrapping generated types |
| `lib/websocket/` | Phoenix Channels client for live chat delivery |
| `lib/auth/` | Session handling; tokens never go to logs or analytics |
| `hooks/` | Cross-feature React hooks |

**Boundaries:**

- Consumes REST under `/api/v1/` and the Chat WebSocket channel.
- Does not read another service's database, hold service credentials, or decide
  visibility/authorization on its own.
- Chat envelopes are opaque handles; the browser never sends plaintext message
  bodies to Chat. Web E2EE parity is an open ADR decision (see
  [open decisions §9](../../docs/architecture/architecture-and-schema.md)).

**Local development:** `bun install` / `bun run dev` once the app is scaffolded
with the chosen bundler. Keep environment variables in `.env.example` only.

**Tests:** unit and component tests next to the feature; end-to-end flows live in
[`tests/end-to-end`](../../tests/README.md).

**Status:** not scaffolded yet.
