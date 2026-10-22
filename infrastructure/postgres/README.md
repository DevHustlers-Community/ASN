# PostgreSQL

Database operations for `social_db`, `chat_db`, `moderation_db`, and `broker_db`.

**Baseline:** PostgreSQL 18.6 locally, via the pinned
`postgres:18.6-alpine3.24` image in [`compose.yaml`](../../compose.yaml).

**Ownership:**

- Each database has exactly one owning service and its own migration history.
- No cross-database foreign keys. Cross-database IDs are soft references.
- No distributed transactions across databases.

## Local development

One PostgreSQL instance hosts all four databases, each with a separate role. The
init script creates:

| Database | Owner |
|---|---|
| `social_db` | `asn_social` |
| `chat_db` | `asn_chat` |
| `moderation_db` | `asn_moderation` |
| `broker_db` | `asn_broker` |
| `chat_db_test` | `asn_chat` |
| `broker_db_test` | `asn_broker` |

The service roles have `LOGIN` only. They are not superusers and cannot create
databases or roles. `PUBLIC` has no `CONNECT` privilege on these databases, so a
service role cannot open another service's database.

The script is
[`init/01-create-databases.sh`](init/01-create-databases.sh). It runs only on an
empty data volume. Use `docker compose down -v` to reset local data and re-run it;
that command is destructive.

PostgreSQL 18 uses `/var/lib/postgresql/18/docker` as `PGDATA` and declares the
volume at `/var/lib/postgresql`. The compose file mounts the named volume at
`/var/lib/postgresql`. Do not change it to the pre-18 path.

## Required extensions

`citext` (Social), plus any extension approved by an ADR. UUIDv7 is generated in
application code by default; PostgreSQL 18 also provides `uuidv7()`, but
database-generated IDs require an ADR.

## Backup and restore

See [`backup-and-restore.md`](backup-and-restore.md). Backups are verified by an
actual restore drill, not by the existence of a file.

## Migration rules

- Migrations are forward-only in production; corrective migrations replace
  rollbacks.
- Destructive changes are split: add, backfill, switch reads/writes, then remove.
- Long locks and index builds on large tables are planned explicitly.
- The `broker_db` migration set is owned by the broker, not by business services.

**Status:** the local init script, role isolation, and compose service are in
place. No application migrations exist yet.
