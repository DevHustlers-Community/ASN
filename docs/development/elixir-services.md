# Elixir service conventions

The Chat service and the Event broker are independent OTP applications. They share
runtime conventions, not code, databases, or domain models.

## Naming

| Service | Folder | OTP app | Root module | Web module |
|---|---|---|---|---|
| Chat | `services/chat-service` | `:asn_chat` | `AsnChat` | `AsnChatWeb` |
| Event broker | `services/event-broker` | `:asn_event_broker` | `AsnEventBroker` | none |

Use the OTP app name, not the folder name, in configuration and commands. Folder
names stay descriptive for humans; module names stay short and stable.

## Baseline

| Component | Version |
|---|---|
| Elixir | 1.20.4 |
| OTP | 29.1.2 |
| Phoenix | 1.8.16 (Chat only) |
| Bandit | 1.13.1 (Chat only) |
| Ecto / Ecto SQL | 3.14 |
| Postgrex | 0.22 |
| PostgreSQL | 18.6 local baseline |

`mix.lock` is committed per service. `.tool-versions` is committed once at the
repository root. Do not install a second Elixir version for one service.

## Layout

```
services/<service>/
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
├── lib/
│   ├── <app>.ex
│   └── <app>/
│       ├── application.ex
│       ├── repo.ex
│       └── <context>/
├── priv/repo/migrations/
├── test/
│   ├── support/
│   └── <app>_web/          # Chat only
└── mix.exs
```

The broker has no web directory. The Chat web layer lives in `lib/asn_chat_web/`.
Domain contexts live in `lib/asn_chat/`; they never import web code.

## Web layer rules (Chat)

- `router.ex` registers routes and pipelines only.
- Controllers validate input shape and map context results to responses.
- Channels handle connection, authorization, and live event framing only.
- Business rules, sequence allocation, membership checks, and envelope validation
  belong in contexts.
- Do not render HTML. The endpoint is JSON-only.
- Do not add LiveView, a dashboard, or an asset pipeline without an ADR.

## OTP rules

- Every long-running process has an owner, a restart strategy, and a shutdown
  path.
- Do not introduce a global writer. Per-conversation serialization belongs in a
  transaction on the conversation row.
- Outbox writers and consumers are supervised processes; they do not block
  request handling.
- The broker has no HTTP listener until ADR 0008. Transport code must not leak
  into storage, routing, or delivery.

## Configuration

- `config/config.exs` holds compile-time configuration shared by environments.
- `config/dev.exs`, `test.exs`, and `prod.exs` hold environment overrides.
- `config/runtime.exs` reads deployment secrets and URLs at boot.
- Service-specific environment variables are prefixed with `CHAT_` or `BROKER_`.
- Never put production secrets in a config file or in `.env.example`.
- Dev and test fallbacks must be clearly non-production placeholders.

## Ecto and migrations

- Only the service's `Repo` touches its database.
- No foreign keys, joins, or transactions across databases.
- Cross-database references are soft references:
  `ref: <db>.<table>.<column>`.
- Migrations are forward-only in production. Use add, backfill, switch, remove.
- Include indexes and constraints in the migration that introduces the data.
- UUIDv7 is generated in application code. PostgreSQL 18 provides `uuidv7()`, but
  the project does not use database-generated IDs by default; changing that
  requires an ADR.
- The broker owns every table in `broker_db`. Business services never connect to
  it.

## Tests

- Use ExUnit. Database tests use `Ecto.Adapters.SQL.Sandbox`.
- Integration tests run against real PostgreSQL, not SQLite or mocks.
- Use fixed opaque envelope vectors for E2EE tests. Never add plaintext fixtures.
- Cover duplicate and out-of-order events, restarts, revoked devices, membership
  removal, and prekey races where the behavior exists.

## Formatting and checks

Run from the service directory:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Run the repository checks from the root:

```bash
python3 scripts/ci/check-changelog.py --all
python3 scripts/ci/check-links.py
```

## Releases

- Elixir services ship as OTP releases.
- `config/runtime.exs` is the only place that reads production secrets.
- The release must start with no dev-only routes, no debug errors, and no
  sensitive connection logging.
- A release is not production-ready until health checks, migrations, and the
  backup/restore drill are documented in the owning service README.
