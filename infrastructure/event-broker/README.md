# Event broker operations

Operational notes for the custom Elixir/OTP broker and `broker_db`.

**What must be observable:**

- Publish rate and publish failures per producing service.
- Per-subscription consumer lag (event ID or timestamp distance).
- In-flight/leased deliveries, lease renewals, and expired leases.
- Retry counts, nack reasons, and dead-letter size.
- Database connection pool saturation and transaction retries.

**Alerts:**

- Consumer lag above the documented safety threshold for security-sensitive
  projections (blocks, bans, membership).
- Dead-letter growth or retry storm.
- Lease expiration spike or broker restart loop.
- Outbox backlog in a producing service.

**Recovery:**

- A broker restart must not lose acknowledged events or duplicate an
  unacknowledged event beyond the at-least-once contract.
- Replay is authorized, scoped to one subscription, and logged.
- A restore from `broker_db` backup is followed by consumer reconciliation; old
  deliveries are expected and must be idempotent.

**Capacity:** single node until measurements justify more. Record throughput,
p95/p99 delivery latency, and database growth per event.

**Status:** the broker scaffold and local database exist. The runbook, metrics, and alerts land with the proof of concept.
