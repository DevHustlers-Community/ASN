# Testing

ASN uses ExUnit for the Elixir services and Bun's built-in test runner (`bun test`)
with `happy-dom` for the web client (`apps/web`).

## Test layers

| Layer | Purpose | Runs against |
|---|---|---|
| Unit | Pure rules, validation, state transitions | No database (or DOM simulator) |
| Integration | Ecto queries, constraints, transactions, repo behavior | Real PostgreSQL |
| Failure | Retries, duplicate delivery, restarts, revoked devices, races | Real PostgreSQL plus controlled failures |
| Contract | OpenAPI and event envelope compatibility | Contracts and generated clients |

Contract tests are added when the first OpenAPI or event schema lands.

## Commands

Chat service:

```bash
cd services/chat-service
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Event broker:

```bash
cd services/event-broker
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Web client:

```bash
bun run test
# or from monorepo root:
bun run --filter '@asn/web' test
```

The Elixir `test` aliases create and migrate the test databases before ExUnit starts.
Start PostgreSQL first:

```bash
docker compose up -d postgres
docker compose ps
```

## Database isolation

- Chat uses `chat_db_test`, owned by `asn_chat`.
- The broker uses `broker_db_test`, owned by `asn_broker`.
- Tests use `Ecto.Adapters.SQL.Sandbox`.
- Tests never connect to a service database they do not own.

## What tests cover today

- Chat: JSON error rendering.
- Broker: application startup and repo connection.
- Web client: utility classes (`cn`), Button variants and foreground contrast, Badge variants with alpha tints, and document theme switching.
- CI: documentation links and changelog formats via Python scripts in `scripts/ci/`.
