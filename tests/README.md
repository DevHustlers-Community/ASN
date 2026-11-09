# Cross-service tests

Tests that no single service can own alone.

| Folder | Contents | Status |
|---|---|---|
| `e2e/` | Full event loop against live processes: Chat outbox → relay → broker → claim → ack → metrics | Available: [`e2e/broker-relay.sh`](e2e/broker-relay.sh) |
| `integration/` | Real service-to-service flows: Social → broker → Chat, Chat → broker → Social | Planned |
| `contract/` | OpenAPI and event schema validation, consumer/provider compatibility | Planned; schema validation currently runs from `scripts/contracts/validate.py` |
| `end-to-end/` | Web, mobile, and admin user journeys against a running stack | Planned |
| `fixtures/` | Shared seed data and event payload examples | Planned |

**Rules:**

- Unit tests stay inside each service/app.
- These tests may start the full stack via `compose.yaml`; they must not require
  a shared production-like database.
- E2EE flows use opaque test envelopes with fixed test vectors; no plaintext
  assertions against server storage.
- Failure-path coverage is part of the requirement: duplicate and out-of-order
  events, broker restart, consumer lag, revoked device, membership removal,
  expired upload, deletion during an active report.

## Cross-service end-to-end

[`e2e/broker-relay.sh`](e2e/broker-relay.sh) runs the full event loop against
live processes: it migrates both databases, boots the broker, issues a real
credential through the admin API, records a chat outbox row, runs the relay,
claims and acknowledges the delivery, and checks the metrics trail. It resets
its own state and picks a random port, so reruns are safe. Prerequisites:
compose PostgreSQL up and both services' dependencies fetched.

**Status:** the happy path is implemented and runs in CI. The failure-path cases
listed above are still to be added to this folder.
