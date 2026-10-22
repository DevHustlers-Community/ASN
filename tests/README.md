# Cross-service tests

Tests that no single service can own alone.

| Folder | Contents |
|---|---|
| `integration/` | Real service-to-service flows: Social -> broker -> Chat, Chat -> broker -> Social |
| `contract/` | OpenAPI and event schema validation, consumer/provider compatibility |
| `end-to-end/` | Web, mobile, and admin user journeys against a running stack |
| `fixtures/` | Shared seed data and event payload examples |

**Rules:**

- Unit tests stay inside each service/app.
- These tests may start the full stack via `compose.yaml`; they must not require
  a shared production-like database.
- E2EE flows use opaque test envelopes with fixed test vectors; no plaintext
  assertions against server storage.
- Failure-path coverage is part of the requirement: duplicate and out-of-order
  events, broker restart, consumer lag, revoked device, membership removal,
  expired upload, deletion during an active report.

**Status:** not written yet; starts after the first vertical slice exists.
