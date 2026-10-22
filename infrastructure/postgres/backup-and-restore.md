# Backup and restore

Backups exist per database: `social_db`, `chat_db`, `moderation_db`, `broker_db`.

## Policy

- Take a full logical backup on a fixed schedule and before any schema change
  that rewrites data.
- Encrypt backups at rest, store them outside the database host, and restrict
  access to the operations role.
- Never treat "the backup file exists" as success. A restore drill is the only
  proof.
- `broker_db` backups restore delivery state; consumers must still reconcile,
  because replay can deliver events that were acknowledged after the backup.

## Restore drill

1. Provision an empty database with the owning service role.
2. Restore the dump into the isolated instance.
3. Run the owning service's migrations up to the current version.
4. Start the service against the restored database and hit its health endpoint.
5. Verify row counts for a small, known set of tables and one read path per
   domain.
6. For `broker_db`, inspect consumer offsets/lag and reconcile projections before
   resuming traffic.
7. Record the drill date, duration, and any drift in
   [`../../docs/operations/`](../../docs/operations/README.md).

## Rules

- Restores go to an isolated instance first; never over a live production
  database.
- Account-deletion and evidence-retention rules still apply after a restore.
- Chat restores contain ciphertext only; a backup is not a way to recover
  plaintext.
- Mobile backups are a separate client-side concern
  ([architecture §3.19](../../docs/architecture/architecture-and-schema.md)).
