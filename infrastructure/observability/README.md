# Observability

Metrics, structured logs, traces, and dashboards.

**Baseline for every service:**

- Health and readiness endpoints.
- Request rate, error rate, and p50/p95/p99 latency per route.
- Database pool usage and slow-query counts.
- Outbox backlog and broker consumer lag.
- Process restarts and supervisor child failures (Elixir services).

**Logging rules:**

- Structured JSON with a request/correlation ID.
- Never log credentials, tokens, decrypted message content, envelope plaintext,
  private keys, backup secrets, or full evidence payloads.
- Log identifiers, not personal data, where a reference is sufficient.

**Dashboards:** one per service plus one for the broker. Dashboards are versioned
in this folder alongside alert rules.

**Tracing:** propagate `trace_id` through REST calls and the event envelope.

**Status:** no dashboards or alert rules yet.
