# Local environment

The local stack is intentionally small: one PostgreSQL 18.6 container plus the
services and web client you choose to run on the host.

## Versions

| Component | Version | Source of truth |
|---|---|---|
| Erlang / OTP | 29.1.2 | [`.tool-versions`](../../.tool-versions) |
| Elixir | 1.20.4-otp-29 | [`.tool-versions`](../../.tool-versions) |
| Bun | 1.4.4 | [`.tool-versions`](../../.tool-versions) |
| Phoenix | 1.8.16 | `services/chat-service/mix.lock` |
| PostgreSQL | 18.6 | [`compose.yaml`](../../compose.yaml) |
| Database image | `postgres:18.6-alpine3.24` | [`compose.yaml`](../../compose.yaml) |

Do not use a floating `latest` database image. Upgrade the tag and run a restore
drill before changing the baseline.

## Ports

| Port | Process | Status |
|---|---|---|
| `5432` | PostgreSQL | Running via compose |
| `4002` | Chat service | Runs when started with `mix phx.server` |
| `4001` | Social API | Reserved; no manifest |
| `4003` | Moderation API | Reserved; no manifest |
| `4004` | Event broker HTTP | Reserved; only if ADR 0008 selects HTTP |
| `3000` | Web | Vite dev server (`apps/web`) |
| `3001` | Admin | Reserved; no manifest |

## Databases and roles

The local init script creates one database per owning service and separate
non-superuser roles. It also creates test databases for the scaffolded services.

| Database | Owner | Purpose |
|---|---|---|
| `social_db` | `asn_social` | Social API |
| `chat_db` | `asn_chat` | Chat service |
| `moderation_db` | `asn_moderation` | Moderation API |
| `broker_db` | `asn_broker` | Event broker |
| `chat_db_test` | `asn_chat` | Chat ExUnit database |
| `broker_db_test` | `asn_broker` | Broker ExUnit database |

Rules enforced locally:

- Each role has `LOGIN` only; no `SUPERUSER`, `CREATEDB`, or `CREATEROLE`.
- `PUBLIC` has no `CONNECT` privilege on these databases. The Chat role cannot
  connect to `social_db`, for example.
- The superuser is `postgres`, used only for administration and init.

## Resetting local databases

To reset the database containers and start fresh:

```bash
docker compose down -v
docker compose up -d postgres
```

This removes the persistent volume and reruns the init script on next start.
