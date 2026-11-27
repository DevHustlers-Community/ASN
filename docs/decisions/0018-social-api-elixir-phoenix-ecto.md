# 0018 - Social API uses Elixir, Phoenix API-only, and Ecto

- Status: accepted
- Date: 2026-11-27
- Supersedes: the Social API portion of planned ADR 0002

## Context

ASN's target architecture originally assigned the Social API to Bun and
TypeScript while Chat and the Event broker use Elixir/OTP. The Social API has not
been scaffolded, so changing its runtime now has no migration cost.

The team is standardizing backend delivery on Elixir and wants high-throughput
REST APIs with optimized PostgreSQL access. Chat already establishes patterns
for Auth0 JWT verification, RFC 9457 errors, transactional outboxes, Ecto
migrations, real-PostgreSQL tests, and OTP releases. The Moderation API remains a
separate TypeScript runtime decision.

## Decision

1. **Runtime:** Social API is an Elixir/OTP application using Phoenix in
   API-only mode and Ecto/Postgrex against `social_db`.
2. **Baseline:** use the repository's existing Elixir 1.20.4 / OTP 29.1.2,
   Phoenix 1.8.17, Ecto 3.14, Postgrex 0.22, Bandit 1.15, and PostgreSQL 18.6
   baselines. Each service keeps its own `mix.lock`.
3. **HTTP surface:** REST only, documented in `contracts/openapi/social-api.yaml`.
   No HTML, LiveView, asset pipeline, GraphQL, or gRPC.
4. **Ownership:** `social_db` remains exclusively owned by Social. No
   cross-database joins, foreign keys, or transactions are introduced.
5. **Integration:** business changes and outbox events commit in one Ecto
   transaction. The existing custom broker remains the only asynchronous
   integration transport.
6. **Performance contract:**
   - Use keyset/cursor pagination with bounded page sizes for feeds, timelines,
     search results, and other large or volatile collections.
   - Select only required columns and return minimal response DTOs; do not load
     large JSON, text, or binary fields for list endpoints.
   - Design indexes from actual access paths and verify them with query plans on
     representative data volumes. Ship indexes with the migration that
     introduces the access pattern.
   - Avoid N+1 queries. Use explicit joins or batched preloads, and measure row
     multiplication before selecting a strategy.
   - Separate feed candidate selection from ranking. Start with bounded SQL
     candidate queries and deterministic ranking; benchmark before introducing
     a cache, search engine, queue, or materialized-view subsystem.
   - Keep denormalized counters asynchronously maintained and rebuildable; they
     are never the only source of truth.
   - Configure bounded connection pools, request/query timeouts, and telemetry
     for query duration, pool queue time, errors, and endpoint latency.
   - Record throughput, p95/p99 latency, CPU, memory, and query-plan evidence in
     performance tests before changing partitioning or scaling strategy.
7. **Testing:** ExUnit with real PostgreSQL for repository and transaction
   behavior, OpenAPI contract tests, query-plan/index tests for critical paths,
   and load tests for feed and timeline endpoints.

## Consequences

- Social and Chat share runtime conventions and operational knowledge, reducing
  delivery and maintenance overhead.
- REST/OpenAPI and event contracts remain unchanged; web, mobile, and admin
  clients are unaffected.
- The Bun runtime policy applies to Moderation only. Bun remains in use for the
  web toolchain unless a separate decision changes it.
- The Social API gains the BEAM runtime's supervision, concurrency, and
  observability model.
- CPU-heavy feed ranking or media processing must be measured and isolated
  before new infrastructure is introduced.
- The planned ADR 0002 is narrowed to the Moderation API or replaced by a future
  Moderation runtime ADR.

## Alternatives considered

- **Bun + TypeScript with Hono/Elysia and Drizzle/Kysely.** Rejected because it
  adds a second backend runtime and duplicates authentication, outbox, database,
  testing, and release patterns already proven in Chat.
- **Node.js LTS + TypeScript.** Rejected for the same polyglot cost; it removes
  Bun but does not improve consistency with the existing backend.
- **Plug + Bandit without Phoenix.** Deferred because Phoenix API-only provides
  established routing, controller, authentication, error, and telemetry
  conventions without HTML or LiveView overhead.
- **Go or Python.** Rejected for the initial implementation because they add a
  third backend runtime and slow delivery without a measured requirement.
