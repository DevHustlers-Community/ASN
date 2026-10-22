# Docker

Container build and local orchestration conventions.

- One `Dockerfile` per deployable service and app, built from the repo root
  context.
- Multi-stage builds: dependency layer, build layer, minimal runtime layer.
- Elixir services ship OTP releases; Bun services ship a production bundle with
  the pinned runtime version.
- `compose.yaml` at the repo root runs local dependencies only: PostgreSQL
  instances for the four databases, object storage, and the edge proxy.
- Health checks are mandatory for every service; `depends_on` alone is not a
  readiness guarantee.
- Images run as a non-root user and never bake in credentials.

**Status:** no Dockerfiles yet; they land with the first scaffolded service.
