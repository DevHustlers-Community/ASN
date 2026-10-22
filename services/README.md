# Services

Backend services. Each service owns exactly one PostgreSQL database, exposes a
REST API documented in [`contracts/openapi/`](../contracts/openapi/README.md),
and publishes domain events through its transactional outbox.

| Service | Runtime | Database | Purpose |
|---|---|---|---|
| [`social-api/`](social-api/README.md) | Bun + TypeScript | `social_db` | Accounts, content, communities, feed |
| [`chat-service/`](chat-service/README.md) | Elixir + Phoenix | `chat_db` | Conversations, encrypted messages, devices |
| [`moderation-api/`](moderation-api/README.md) | Bun + TypeScript | `moderation_db` | Reports, cases, appeals, audit |
| [`event-broker/`](event-broker/README.md) | Elixir/OTP + Ecto | `broker_db` | Durable event delivery |

## Rules shared by all services

- **One owner per table.** Never read or write another service's database.
  Cross-database IDs are soft references (`ref: db.table.column`).
- **No cross-database transactions.** Use the outbox + broker for integration.
- **REST only** for HTTP APIs. No GraphQL or gRPC without an approved ADR.
- **Idempotent consumers.** Delivery is at-least-once; deduplicate on `event_id`
  and ignore stale data with `aggregate_version`.
- **Contracts first.** Change the OpenAPI/event schema before changing code, and
  validate contracts in CI.
- **No plaintext chat.** Chat stores opaque envelopes only; logs, events, push
  payloads, and analytics never carry message content or private keys.
- **Migrations are per service.** Each service runs its own migration workflow;
  there is no cross-service migration.

## Local development

Each service README documents its own setup. Shared dependencies (PostgreSQL,
object storage, proxy) are described in
[`infrastructure/`](../infrastructure/README.md). The Chat and broker scaffolds
run against local PostgreSQL; their contract-first health endpoints land with the
first API contract.
