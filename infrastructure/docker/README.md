# Docker

Container build and local orchestration conventions.

## Local compose

[`compose.yaml`](../../compose.yaml) at the repository root runs local
dependencies. Today that is one PostgreSQL 18.6 instance for all four service
databases and their local test databases.

- Image tags are pinned. PostgreSQL uses `postgres:18.6-alpine3.24`.
- The data volume is mounted at `/var/lib/postgresql`, the PostgreSQL 18+ volume
  path. Do not use the pre-18 `/var/lib/postgresql/data` path.
- `infrastructure/postgres/init/` is mounted read-only at
  `/docker-entrypoint-initdb.d`. It runs only on an empty volume.
- The health check uses `pg_isready`; `depends_on` alone is not a readiness
  guarantee.
- Local credentials come from `.env` placeholders. No secret is baked into the
  image or the compose file.

See [`docs/development/local-environment.md`](../../docs/development/local-environment.md)
for commands and database names.

## Application images

- One `Dockerfile` per deployable service and app, built from the repo root
  context.
- Multi-stage builds: dependency layer, build layer, minimal runtime layer.
- Elixir services ship OTP releases; Bun services ship a production bundle with
  the pinned runtime version.
- Images run as a non-root user and never bake in credentials.
- Every HTTP service gets a health check before it is considered deployable.

**Status:** the local PostgreSQL compose service exists. No application
Dockerfile exists yet; they land with the first deployable service.
