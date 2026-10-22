# Infrastructure

Local and deployed infrastructure. This folder contains configuration and
operational documentation, not application logic.

| Folder | Purpose |
|---|---|
| [`docker/`](docker/README.md) | Image and compose conventions |
| [`proxy/`](proxy/README.md) | Edge routing and TLS termination |
| [`postgres/`](postgres/README.md) | Development databases, migration and backup rules |
| [`event-broker/`](event-broker/README.md) | Broker operations, recovery, retention |
| [`observability/`](observability/README.md) | Metrics, logs, dashboards, alerts |
| [`deployment/`](deployment/README.md) | Development, staging, production environments |

**Rules:**

- No secrets in this folder. Use `.env.example` names and placeholders.
- Each service owns its database and migrations; there is no shared schema.
- Kubernetes is not required for the first deploy. Start with compose locally
  and a simple single-host or managed deployment.
- Backups and a tested restore exist for every database, including `broker_db`.
