# 0011 - Elixir and PostgreSQL baseline

- Status: accepted
- Date: 2026-10-22
- Supersedes: -

## Context

The repository has architecture documentation but no runnable service baseline.
The Chat service and Event broker need reproducible Elixir manifests, and local
development needs a database version that matches the target. Without pinned
versions and a fixed scaffold shape, the first migrations would land on an
unstable toolchain.

The broker transport is still open and must not be selected implicitly by a
scaffold.

## Decision

- Pin Elixir 1.20.4 on OTP 29.1.2 in `.tool-versions`.
- Use Phoenix 1.8.16 for the Chat service, API-only: no HTML, assets, LiveView,
  dashboard, gettext, or mailer. Phoenix Channels remain the live-delivery
  mechanism when that work starts.
- Use plain Elixir/OTP plus Ecto and Postgrex for the Event broker. Do not add
  Phoenix, Plug, Bandit, an HTTP endpoint, or a listener until the broker
  transport ADR is accepted.
- Use PostgreSQL 18 as the database baseline. Local development pins
  `postgres:18.6-alpine3.24` and one container with separate service roles,
  databases, and test databases.
- Keep UUIDv7 generation in application code through one vetted library per
  runtime. PostgreSQL 18 provides `uuidv7()`, but database-generated IDs require
  a separate decision.
- Commit each service's `mix.lock`; keep service dependencies independent instead
  of introducing an umbrella.

## Consequences

- Chat and broker compile, format, test, and boot against local PostgreSQL.
- The broker cannot accidentally commit to HTTP polling or a persistent
  connection before the transport decision. Adding a transport later is an
  additive change.
- The two services duplicate a small amount of configuration and dependency
  declarations. This is accepted to preserve independent deployment and database
  ownership.
- PostgreSQL 18's image uses `/var/lib/postgresql` as the volume path; local
  compose and runbooks must not use the pre-18 `/var/lib/postgresql/data` path.
- Service lockfiles must be updated deliberately. A floating image tag or an
  uncommitted lockfile is a defect.

## Alternatives considered

- **Keep PostgreSQL 16.** Rejected because the target baseline is 18+, and the
  local environment should match the target major version.
- **Use Phoenix for the broker.** Deferred. It would select an HTTP transport
  before the transport ADR and add web dependencies to an OTP-first service.
- **Use an umbrella for both Elixir services.** Rejected. The services have
  separate owners, databases, and release lifecycles.
- **Use database-generated UUIDv7.** Deferred. Application generation keeps the
  identifier contract identical across TypeScript and Elixir runtimes.
