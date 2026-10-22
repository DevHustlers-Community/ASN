# PostgreSQL

Database operations for `social_db`, `chat_db`, `moderation_db`, and `broker_db`.

**Ownership:**

- Each database has exactly one owning service and its own migration history.
- No cross-database foreign keys. Cross-database IDs are soft references.
- No distributed transactions across databases.

**Local development:** one PostgreSQL instance may host all four databases, each
with a separate role. The service role never has superuser rights and cannot
access another service's database.

**Required extensions:** `citext` (Social), plus any extension approved by an ADR.
UUIDv7 is generated in application code, not assumed from the database.

**Backup and restore:** see [`backup-and-restore.md`](backup-and-restore.md).
Backups are verified by an actual restore drill, not by the existence of a file.

**Migration rules:**

- Migrations are forward-only in production; corrective migrations replace
  rollbacks.
- Destructive changes are split: add, backfill, switch reads/writes, then remove.
- Long locks and index builds on large tables are planned explicitly.
- The `broker_db` migration set is owned by the broker, not by business services.

**Status:** the dev initialization script and backup/restore runbook are not
written yet.
