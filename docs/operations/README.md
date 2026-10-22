# Operations

| Document | Purpose |
|---|---|
| `migrations.md` | Per-service migration policy and rollout order |
| `backups.md` | Database backups and verified restore drills |
| `monitoring.md` | Metrics, logs, alerts, dashboards |
| `incident-response.md` | Severity levels, roles, communication |
| `event-broker-recovery.md` | Broker restore, replay, and reconciliation |

**Rules:**

- Every runbook is written against a real environment and tested at least once.
- Backups are not considered valid until a restore succeeds.
- Incident response assumes the broker may redeliver events; recovery includes a
  reconciliation step for affected projections.
- No runbook asks an operator to log secrets or decrypted chat content.

**Status:** not written yet. Start with `backups.md` and
`event-broker-recovery.md`.
