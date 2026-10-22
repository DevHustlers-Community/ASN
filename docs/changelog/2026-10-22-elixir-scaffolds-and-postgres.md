---
date: 2026-10-22
type: feat
scope: services
summary: Scaffold the Chat and Event broker apps and pin the PostgreSQL 18 baseline
breaking: false
adr: "0011"
contracts: -
---

# Scaffold the Chat and Event broker apps and pin the PostgreSQL 18 baseline

## Change

- Added `services/chat-service` as an API-only Phoenix 1.8.16 application
  (`asn_chat` / `AsnChat` / `AsnChatWeb`) with Ecto, Bandit, and a JSON endpoint.
- Added `services/event-broker` as a plain Elixir/OTP application
  (`asn_event_broker` / `AsnEventBroker`) with Ecto and Postgrex, no HTTP adapter
  or listener.
- Pinned Elixir 1.20.4 / OTP 29.1.2 in `.tool-versions`. Pinned service
  dependencies in `mix.lock` (Phoenix 1.8.16, Bandit 1.13.1, Ecto 3.14.2,
  Ecto SQL 3.14.0, Postgrex 0.22.4).
- Added root `compose.yaml` with PostgreSQL 18.6 (`postgres:18.6-alpine3.24`),
  health check, persistent volume at `/var/lib/postgresql`, and an init script
  that creates four roles, four service databases, and two test databases.
- Added the init script with non-superuser roles and no `PUBLIC` connect
  privilege, so a service role cannot open another service's database.
- Added `.tool-versions`, service code maps, development guides, and updated
  architecture, glossary, service, infrastructure, and agent documentation.
- Recorded ADR 0011 for the Elixir/Phoenix and PostgreSQL baseline and the
  transport-neutral broker scaffold.

## Why

The repository had a documented architecture but no runnable Elixir service
baseline. The first migrations and contracts need a reproducible toolchain, a
database major that matches the target, and a broker that does not silently
choose the still-open transport. This change makes Chat and the broker compile,
boot, and test locally without adding product behavior.

## Verification

- `docker compose config` — valid configuration.
- `docker compose up -d postgres` — PostgreSQL 18.6 started and reached
  `healthy`.
- `docker compose exec postgres psql ...` — six databases owned by the four
  service roles; all roles have `rolsuper = false`, `rolcreatedb = false`, and
  `rolcreaterole = false`.
- `psql postgres://asn_chat:.../social_db` — rejected with `permission denied for
  database "social_db"`.
- `sh -n infrastructure/postgres/init/01-create-databases.sh` — syntax OK.
- `services/chat-service`: `mix deps.get`, `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix test` — 2 tests passed.
- `services/event-broker`: `mix deps.get`, `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix test` — 1 test passed.
- `python3 scripts/ci/check-changelog.py --all` — change records OK.
- `python3 scripts/ci/check-links.py` — relative documentation links OK.

No OpenAPI or event contracts, migrations, health endpoints, Dockerfiles, or CI
workflows were added, so none were tested.

## Follow-ups

- Add contract-first health endpoints and OpenAPI files.
- Add CI for both Elixir services against PostgreSQL 18.
- Accept ADR 0008 before adding the broker transport.
- Add Chat migrations only after the E2EE envelope decisions are settled.
- Scaffold the Social and Moderation APIs.
