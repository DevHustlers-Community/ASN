# Local environment

The local stack is intentionally small: one PostgreSQL 18.6 container plus the
Elixir services you choose to run on the host.

## Versions

| Component | Version | Source of truth |
|---|---|---|
| Erlang / OTP | 29.1.2 | [`.tool-versions`](../../.tool-versions) |
| Elixir | 1.20.4-otp-29 | [`.tool-versions`](../../.tool-versions) |
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
| `3000` | Web | Reserved; no manifest |
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
- The broker does not get access to business databases.

The init script lives in
[`infrastructure/postgres/init/01-create-databases.sh`](../../infrastructure/postgres/init/01-create-databases.sh).
It runs only on an empty data volume.

## Environment variables

Copy the example file and edit local values:

```bash
cp .env.example .env
```

| Variable | Purpose |
|---|---|
| `POSTGRES_PASSWORD` | Local superuser password |
| `ASN_DB_PASSWORD` | Password assigned to all local service roles |
| `POSTGRES_PORT` | Host port for PostgreSQL, default `5432` |
| `SOCIAL_DATABASE_URL` | Social API connection URL |
| `CHAT_DATABASE_URL` | Chat service connection URL |
| `MODERATION_DATABASE_URL` | Moderation API connection URL |
| `BROKER_DATABASE_URL` | Event broker connection URL |
| `CHAT_TEST_DATABASE_URL` | Chat test connection URL |
| `BROKER_TEST_DATABASE_URL` | Broker test connection URL |
| `CHAT_SERVICE_PORT` | Chat HTTP port, default `4002` |
| `SECRET_KEY_BASE` | Chat signing secret; required in production |

`.env` is ignored by Git. Do not put real credentials in `.env.example`, service
config, tests, or documentation. If you change `ASN_DB_PASSWORD`, update the four
service URLs and the two test URLs to match.

## Compose lifecycle

```bash
# Start PostgreSQL
docker compose up -d postgres

# Status and health
docker compose ps

# Logs
docker compose logs -f postgres

# Stop without deleting data
docker compose down

# Destroy local data and re-run initialization
docker compose down -v
docker compose up -d postgres
```

`docker compose down -v` deletes the `asn_postgres-data` volume. Treat it as a
destructive reset. Initialization is not re-run on an existing volume.

PostgreSQL 18 changed the image's default `PGDATA` to
`/var/lib/postgresql/18/docker` and the declared volume to
`/var/lib/postgresql`. The compose file mounts the named volume at
`/var/lib/postgresql`; do not change it to the pre-18 `/var/lib/postgresql/data`
path.

## Manual inspection

```bash
docker compose exec postgres psql -U postgres -d postgres
```

From the host:

```bash
psql "postgres://asn_chat:change_me@localhost:5432/chat_db"
```

Use the service role only for its own database. Cross-database access must fail.
