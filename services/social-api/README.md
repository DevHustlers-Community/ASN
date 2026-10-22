# Social API

Bun + TypeScript REST API that owns `social_db`.

**Owns:** accounts and identity mapping, profiles, privacy settings, follows,
platform-wide blocks, posts, media metadata, comments, likes, reposts, hashtags,
feed inputs and ranking, articles and revisions, communities and roles, channel
metadata, notifications, plans/subscriptions/feature flags, account deletion
workflow, activity calendar and login streaks.

**Does not own:** friendships, conversations, messages, chat devices, reports,
cases, or the event log.

**Planned layout (`src/`):**

| Path | Purpose |
|---|---|
| `app.ts`, `server.ts` | Application assembly and process entry |
| `config/` | Environment and settings parsing (fail fast) |
| `modules/` | auth, users, profiles, relationships, posts, comments, reactions, feed, communities, hashtags, search, subscriptions, notifications, reports |
| `events/` | Outbox writer, publishers, consumers |
| `infrastructure/` | Database, broker client, object storage, cache, logging |
| `middleware/` | Auth, request ID, validation, error mapping |

**Module shape:** `routes.ts`, `controller.ts`, `service.ts`, `repository.ts`,
`schemas.ts`, optional `policies.ts` and `errors.ts`. Keep business rules in the
service layer, never in route handlers.

**Boundaries:**

- Emits `user.*`, `community.*`, `channel.*`, `member.*`, `subscription.*`
  events; consumes `friendship.*` for `friend_edges`.
- Never reads `chat_db`, `moderation_db`, or `broker_db`.
- Private community content never reaches public feeds, search, trends,
  notifications, or global reposts - enforce through one visibility policy.

**Tests:** unit (`tests/unit`), integration with a real PostgreSQL instance
(`tests/integration`), OpenAPI contract tests (`tests/contract`).

**Status:** not scaffolded. HTTP framework, query layer, and migration tool are
open ADR decisions.
