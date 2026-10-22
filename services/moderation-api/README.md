# Moderation API

Bun + TypeScript REST API that owns `moderation_db`.

**Owns:** report reasons, reports, evidence snapshots, cases, case notes,
moderation actions, appeals, user strikes, announcements, and the staff audit
log.

**Does not own:** users, content, messages, or bans as account state. Those live
in Social and Chat; Moderation requests a decision and the owner applies it.

**Planned layout (`src/`):**

| Path | Purpose |
|---|---|
| `modules/admin-auth/` | Staff authentication and role checks |
| `modules/reports/` | Report intake, including client-submitted E2EE evidence |
| `modules/moderation-queue/` | Case assignment, SLA, work queue |
| `modules/bans/` | Bans and strikes as requests to owning services |
| `modules/appeals/` | Appeals; reviewer must differ from the original moderator |
| `modules/announcements/` | Staff announcements |
| `modules/audit-logs/` | Append-only staff audit |
| `modules/statistics/` | Moderation metrics |
| `events/` | Outbox publishers and consumers |
| `infrastructure/` | Database, broker client, logging |

**Hard rules:**

- Evidence for an E2EE message is what the reporter explicitly submitted, with
  provenance and a content hash. It is not a server-side snapshot of live chat.
- Evidence access is audited; media lives in a restricted bucket.
- `audit_log` is append-only: the application role can `INSERT` only.
- Moderation never updates `social_db` or `chat_db` directly.
- One active case per `(target_type, target_id)` via a partial unique index.

**Tests:** unit, integration, contract; plus permission tests proving the app
role cannot update or delete audit rows.

**Status:** not scaffolded.
