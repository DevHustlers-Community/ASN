# Getting started

This guide covers the parts of ASN that run today: the local PostgreSQL instance,
the Chat service scaffold, the Event broker scaffold, and the web client scaffold (`apps/web`).
Social, Moderation, admin, and mobile have no manifests yet.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| mise | current | Reads [`.tool-versions`](../../.tool-versions) |
| Erlang / OTP | 29.1.2 | Installed by mise |
| Elixir | 1.20.4-otp-29 | Installed by mise |
| Bun | 1.4.4 | Installed by mise / bun.sh; runs web and TS scripts |
| Docker + Compose | Docker 29+, Compose 5+ | Runs PostgreSQL locally |
| Python | 3.10+ | Runs the repository checks in `scripts/ci/` |

## 1. Install the toolchains

```bash
mise install
elixir --version
bun --version
```

`elixir --version` must report Elixir 1.20.4 and Erlang/OTP 29. `bun --version` must report 1.4.4.

## 2. Start local PostgreSQL

From the repository root:

```bash
cp .env.example .env
docker compose up -d postgres
docker compose ps
```

Wait for the `postgres` service to become `healthy`. The first start runs the
init script that creates the service roles, databases, and test databases. The
script does not run again while the volume exists.

Connection URLs are listed in [`.env.example`](../../.env.example). The default
local password is the placeholder `change_me`; change it in `.env` if you need a
different local value. Never commit `.env`.

See [`local-environment.md`](local-environment.md) for ports, database names, and
reset instructions.

## 3. Run the Chat service scaffold

```bash
cd services/chat-service
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

The service starts on `http://localhost:4002`. There are no routes yet, so `/api`
returns a 404. Stop it with `Ctrl+C`.

## 4. Run the Event broker scaffold

In a second terminal:

```bash
cd services/event-broker
mix deps.get
mix ecto.create
mix ecto.migrate
mix run --no-halt
```

The broker starts its OTP application and PostgreSQL repo, then waits. It has no
listener because the transport decision is open
([ADR 0008](../decisions/README.md)). Stop it with `Ctrl+C`.

## 5. Run the web client scaffold

In a third terminal:

```bash
bun install
bun run dev:web
```

The Vite dev server starts on `http://localhost:3000`. Stop it with `Ctrl+C`.

## 6. Verify

For each Elixir service:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

For the web client:

```bash
bun run --filter '@asn/web' typecheck
bun run --filter '@asn/web' lint
bun run --filter '@asn/web' test
bun run --filter '@asn/web' build
```

For the repository:

```bash
python3 scripts/ci/check-changelog.py --all
python3 scripts/ci/check-links.py
```

`mix test` uses the real local PostgreSQL test database. If PostgreSQL is not
running, the test alias fails before ExUnit starts.

## What works today

- The Elixir and Bun toolchains are pinned and reproducible.
- PostgreSQL 18.6 runs locally with four service roles and isolated databases.
- Chat and broker manifests resolve, compile, format, and boot.
- The web client (`apps/web`) compiles, tests, and builds under Bun with offline fonts and design tokens.
- The Chat endpoint and broker repo connect to their databases.

## What does not work yet

- No product REST endpoints, OpenAPI files, event schemas, migrations, or
  background jobs.
- No Social, Moderation, admin, or mobile manifests.
- No Dockerfile for an application service and no CI workflow for Elixir.
- No health endpoints; they land with the first HTTP contract.
