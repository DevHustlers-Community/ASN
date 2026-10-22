# Testing

ASN uses ExUnit for the Elixir services. There is no JavaScript test runner yet
because the TypeScript applications have no manifests.

## Test layers

| Layer | Purpose | Runs against |
|---|---|---|
| Unit | Pure rules, validation, state transitions | No database |
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

The `test` aliases create and migrate the test databases before ExUnit starts.
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
- Never point a test at a shared or production database.

## Test layout

Current scaffold:

| Path | Contents |
|---|---|
| `services/chat-service/test/asn_chat_web/` | Generated error-rendering tests |
| `services/chat-service/test/support/conn_case.ex` | Connection and sandbox setup |
| `services/chat-service/test/support/data_case.ex` | Database and sandbox setup |
| `services/event-broker/test/asn_event_broker_test.exs` | Application smoke test |
| `services/event-broker/test/support/data_case.ex` | Database and sandbox setup |

Planned layers as features land: `test/unit/`, `test/integration/`, and
`test/failure/` inside the owning service. Add directories only with tests.

## Required failure paths

- Duplicate and out-of-order events.
- Broker restart with in-flight leases.
- Database disconnect during publish or delivery.
- Consumer lag and dead-letter replay.
- Revoked device receiving an envelope.
- Membership removal during message fan-out.
- Prekey race.
- Account deletion during an active report.
- Expired upload.

## E2EE test rules

- Use fixed opaque envelope vectors. `dev-opaque-v1` has the same shape as
  production envelopes.
- Never add a plaintext message body to a server test, fixture, snapshot, log
  assertion, or event payload.
- Do not weaken encryption, authorization, or validation to make a test pass.

## Current status

The scaffolds have two Chat tests (JSON error rendering) and one broker smoke
test. No integration, contract, or failure tests exist yet because there is no
product behavior to test.
