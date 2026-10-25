# 0008 - Broker transport and delivery contract

- Status: accepted
- Date: 2026-10-25
- Supersedes: -

## Context

The event broker is a custom Elixir/OTP service persisted in `broker_db`
([ADR 0011](0011-elixir-and-postgres-baseline.md)). It was scaffolded
transport-neutral on purpose: no HTTP dependency, endpoint, or listener until
this decision. The architecture document (§9.3) defers the transport choice,
lease renewal, in-flight limits, retry/backoff defaults, dead-letter and event
log retention, the payload size limit, and replay authorization to this ADR.

Facts that constrain the choice:

- Consumers are a fixed, small set of long-lived backend services (Chat, Social
  API, Moderation API), never end-user clients. Clients reach services; services
  integrate through events.
- HTTP application APIs are REST only, and a custom wire protocol is an
  explicit non-goal for the first release.
- Delivery is at-least-once. Consumers deduplicate on `event_id` and reject
  stale `aggregate_version` values. Ordering exists per aggregate only.
- The broker core must stay a plain OTP application: storage and delivery logic
  must not depend on Phoenix, Plug, or Bandit (see the broker `CODE_MAP.md`).
- Publishers are outbox relays running inside each producing service; they
  publish after their local transaction commits.

Two external reviews of the first draft of this ADR identified gaps that had
to be closed before acceptance: retention interacting with dead-letter replay,
conflicting content under a duplicate `event_id`, ordering semantics around
dead letters and shared aggregate versions, lease validity rules,
new-subscription backfill policy, and subscription/credential lifecycle. This
revision settles each of them.

## Decision

### 1. Transport: HTTP claim-based pull with long-polling

- The broker never opens an outbound connection. Relays and consumers call the
  broker over REST; the broker only answers.
- A consumer claims work with `POST /v1/subscriptions/{name}/claims` carrying
  `max` (delivery cap) and an optional `wait_ms` (up to 20000).
- Waiting works without busy polling: on claim arrival the broker checks the
  database once; if nothing is claimable it parks the request on an in-process
  waiter registry. Publishing and due-timers (backoff, lease expiry) wake the
  parked claims, which then run a short claim transaction. A configurable
  fallback sweep (default 1 s) re-checks regardless, so correctness never
  depends on wakeups. No transaction or row lock is held while parked.
- The broker is single-node: publishers and claim handlers share one BEAM
  instance, so in-process wakeup suffices. `LISTEN/NOTIFY` is an optional
  future wakeup signal (never a delivery transport) if the broker ever spans
  nodes.
- A push adapter (broker-initiated POST to consumer endpoints) may be added
  later as an edge adapter that claims on behalf of a consumer. The delivery
  state machine, leases, and acknowledgements do not change. This ADR does not
  commit to push.

### 2. REST surface (v1)

| Operation | Request |
|---|---|
| Publish event | `POST /v1/events` |
| Claim deliveries | `POST /v1/subscriptions/{name}/claims` |
| Acknowledge | `POST /v1/deliveries/{id}/ack` |
| Fail / reschedule | `POST /v1/deliveries/{id}/nack` |
| Renew lease | `POST /v1/deliveries/{id}/extend` |
| Skip dead delivery | `POST /v1/deliveries/{id}/skip` (admin scope) |
| Inspect deliveries | `GET /v1/deliveries?state=dead&subscription=...` |
| Replay dead letters | `POST /v1/dead-letters/replay` (admin scope) |
| Create subscription | `POST /v1/subscriptions` (admin scope) |
| List subscriptions | `GET /v1/subscriptions` (admin scope) |
| Update subscription | `PATCH /v1/subscriptions/{name}` — pause/resume, filters (admin scope) |
| Health | `GET /healthz`, `GET /readyz` |

Claim responses carry the canonical event envelope defined in
`contracts/events/` plus delivery metadata (`delivery_id`, `lease_token`,
`lease_expires_at`, `attempts`). The envelope schema is the first contract
artifact to land, before the broker proof of concept.

### 3. Delivery state machine

States are stored as `text` with a `CHECK` constraint: `pending`, `leased`,
`delivered`, `dead`, `skipped`. `delivered` and `skipped` are terminal; `dead`
is terminal until an administrator acts on it.

- claim: `pending → leased` (attempts increment **at claim time**, so crashed
  consumers consume retry budget; a fresh lease token is issued)
- ack: `leased → delivered`
- nack or lease expiry with attempts remaining: `→ pending` (backoff through
  `next_attempt_at`; lease fields cleared)
- nack or lease expiry with attempts exhausted: `→ dead`
- admin replay: `dead → pending` (attempts reset to zero for a fresh budget)
- admin skip: `dead → skipped` (never delivered; explicit operator decision)

`CHECK` constraints pin field/state pairing: `lease_expires_at` present only
when `leased`; `lease_token_hash` present when `leased` **or** `delivered`
(the delivered row keeps the final lease's hash for the idempotent-ack
comparison); `delivered_at` only when `delivered`; `dead_lettered_at` only
when `dead`; `skipped_at` only when `skipped`; `attempts >= 0`;
`max_attempts > 0`.

### 4. Lease validity

- Lease (visibility timeout): 30 s by default; `extend` adds 30 s. Both are
  configuration.
- Every grant (claim, or reaper reclaim after expiry) issues a fresh
  uniform-random lease token; only a SHA-256 hash of the token is stored and
  tokens are never logged.
- `ack`, `nack`, and `extend` require `state = leased`, a matching token, and
  `lease_expires_at > now()` evaluated with **database time**. An expired lease
  fails with 409; `extend` never revives an expired lease. There is no grace
  period: redelivery plus consumer-side deduplication absorbs the race.
- `ack` idempotency is defined exactly: a repeated `ack` carrying the token
  of the lease that produced the `delivered` state returns 200 and changes
  nothing — the delivered row retains that final lease token hash solely for
  this comparison (`lease_expires_at` applies only while `leased`). Any other
  token — in particular a superseded token after the delivery was re-leased to
  another claim — returns 409 and cannot change any state: only the current
  lease's token can `ack`, `nack`, or `extend`, and once a new lease is
  granted the old token is dead.

### 5. Idempotent publish and content integrity

- The broker computes a SHA-256 `content_hash` over the canonical
  serialization of the **complete received envelope** — every field that
  determines the event's identity and content (`type`, `schema_version`,
  `occurred_at`, `aggregate_type`, `aggregate_id`, `aggregate_version`,
  `trace_id`, `payload`), not the payload alone. Publish with a new `event_id`
  returns 201. The same `event_id` with the same stored `content_hash` and the
  same publisher returns 200 and changes nothing. The same `event_id` with a
  different `content_hash` — a difference in **any** effective field — or a
  different publisher returns **409 Conflict** and changes nothing.
- `publisher` comes exclusively from the authenticated credential, never from
  the request body. A credential may restrict publishable event types
  (`allowed_event_types`, NULL = all).
- Exactly **one event per `aggregate_version`** is a deliberate constraint of
  the event model, not an incidental index choice: each business transaction
  on an aggregate produces the next strictly increasing version, and exactly
  one event carries it. Uniqueness within `(aggregate_type, aggregate_id)` is
  enforced by a partial unique index; a different `event_id` reusing a taken
  version is a producer-contract violation and returns 422.
- The ordering guarantee starts in the producer's outbox relay. Per aggregate,
  a relay publishes version N and does not publish N+1 until N is definitively
  accepted — 201 (accepted) or 200 (accepted duplicate). On a timeout or an
  ambiguous outcome the relay retries the **same** `event_id` with identical
  content, which idempotent publish makes safe, and only then advances. A 409
  or 422 response is a producer bug: the relay halts that aggregate and
  alerts rather than skipping ahead. Relay stall, publish timeout with
  retry, and out-of-order publication attempts are required failure-path
  tests.
- Broker deduplication prevents duplicate log entries and duplicate fan-out.
  It does not make consumers idempotent: consumer-side inbox deduplication on
  `event_id`, atomic with the business effect in the consumer's own database,
  remains mandatory (architecture rule).

### 6. Ordering and head-of-line blocking

- A delivery is claimable only when it is the **earliest non-terminal
  delivery** for its `(subscription, aggregate_type, aggregate_id)`, ordered by
  `aggregate_version`. Later versions are blocked while an earlier version is
  non-terminal — including `dead` and backoff-waiting. Head-of-line blocking is
  deliberate: a poison event stalls its aggregate until an administrator
  replays or skips it. There is no implicit skipping.
- Events without aggregate fields are unordered and bounded only by the
  per-subscription in-flight cap.
- Per-subscription in-flight cap: 10 deliveries (configuration). Consumers
  control pacing through the claim `max`.
- The claim transaction takes a short `FOR UPDATE` lock on the subscription
  row, serializing claims per subscription; it is never held during long-poll
  waiting. A partial unique index
  `ON deliveries (subscription_id, aggregate_type, aggregate_id) WHERE
  state = 'leased'` enforces the one-lease-per-aggregate invariant at the
  database level regardless of code bugs. If subscription-lock contention is
  ever measured, a `FOR UPDATE SKIP LOCKED` claim path is the evaluated
  alternative; it is not adopted speculatively.
- Consumers still reject stale `aggregate_version` values: at-least-once
  redelivery can resend an earlier version after a crash.

### 7. Subscription lifecycle

- Fan-out happens at publish time. New subscriptions start receiving events
  from their creation onward; there is **no automatic backfill** of history.
  Historical backfill for new consumers is a separate explicit decision, not
  part of v1.
- `paused`: deliveries keep being created; claims return 409 with error code
  `subscription_paused` until the subscription is resumed.
- `event_types`: NULL means all event types; an empty array is rejected
  (`CHECK` on cardinality).
- A subscription is bound to one consuming service (`consumer`). Claims are
  authorized only for a `consume`-scoped credential of that service.

### 8. Retention and replay availability (defined separately)

Retention is a deletion policy; replay availability is what can still be
redelivered. The two are defined explicitly and are not the same window:

- **Retention (deletion policy):** delivered deliveries are purgeable after 24
  hours; dead and skipped deliveries after 30 days. An event is purgeable
  only when it is older than the 7-day event-log floor **and** no delivery
  referencing it is non-terminal or within its own retention window.
  Retention runs as a broker worker; purge deletes are batched.
- **Replay availability (v1):** the only replay mechanism in v1 is
  dead-letter replay, and it works for the **entire** dead-delivery retention
  because dependency-aware retention keeps the event alive as long as its
  dead letter lives. The 7-day event-log figure is a retention floor, **not**
  a replay promise: events whose deliveries are all delivered and purged are
  not replayable in v1, and general historical replay or backfill does not
  exist in v1 (§7). Dead-letter replay requires the `admin` scope and is
  audited.

### 9. Authentication and authorization

- v1 uses per-credential bearer tokens. `service_credentials` stores:
  `credential_id` (UUIDv7), `service_name`, `token_hash` (SHA-256), `scopes`,
  `allowed_event_types` (NULL = all, publish scope only), `created_at`,
  `expires_at` (nullable), `revoked_at` (nullable). Comparison is
  constant-time.
- A service may hold multiple active credentials, enabling zero-downtime
  rotation: create the new credential, distribute it, revoke the old one.
- The first admin credential is seeded from the `BROKER_ADMIN_TOKEN`
  environment variable at first boot only (when the credentials table is
  empty), stored hashed. Later rotation happens through the admin API.
- Administrative actions (replay, skip, subscription and credential changes)
  are recorded in an immutable, durable `audit_log` in `broker_db`, written
  **in the same database transaction** as the state change they describe: an
  admin operation either commits together with its audit entry or not at all.
- Scopes: `publish` for relays, `consume` for claim/ack/nack/extend, `admin`
  for inspection, replay, skip, and subscription/credential management.
- mTLS is deferred to the platform-wide service-to-service authentication
  decision (§9.1 of the architecture document). Adopting it later changes the
  edge adapter only.

### 10. Limits

- The 256 KiB limit applies to the **entire HTTP request body**, enforced at
  the adapter before parsing; oversized requests fail with 413. Large content
  travels by claim-check reference (an object-storage key), never inline, per
  the event contract rules.

### 11. Operations and telemetry

- Telemetry from day one: per-subscription oldest pending delivery age,
  consumer lag, dead count, lease-expiry rate, empty-claim rate, claim wait
  latency, publish rate, duplicate-publish and conflict counts.
- Logs are structured; tokens and event payloads are never logged.
- `deliveries` is update-hot: migrations set a lower `fillfactor` and tune
  autovacuum. Time-based partitioning of `events` is deferred until
  measurements justify it; it is not a v1 goal.

All numeric values above are defaults exposed through configuration. Changing a
default is a configuration change, not a new ADR.

## Consequences

- The broker gains `plug` and `bandit` dependencies and becomes callable over
  HTTP, while its core remains a plain OTP application.
- Delivery latency is near-real-time without persistent connections and
  without busy polling; the fallback sweep bounds wakeup loss.
- Duplicate delivery remains possible (lease expiry, redelivery after a crash).
  Consumers must deduplicate on `event_id` and reject stale `aggregate_version`
  values. This is already an architecture rule; under this ADR it becomes
  load-bearing for every consumer.
- Head-of-line blocking means one poison event stalls its aggregate until an
  administrator acts. Dead-letter count and oldest-pending-age alerting are
  operational requirements from day one.
- Producers must publish unique, increasing `aggregate_version` values per
  aggregate and in order per aggregate from their outbox relays. The broker
  rejects violations instead of silently misordering.
- Consumers own pacing and concurrency. The broker has no endpoint registry
  and no outbound HTTP path to operate or secure.
- There is no global ordering and no backfill of history for new
  subscriptions. Services needing either must not rely on the broker for it.
- Exactly-once delivery, clustering, partition leadership, a custom disk log,
  and a custom wire protocol remain non-goals per the broker README
  first-release scope.

## Alternatives considered

- **Push/webhook delivery.** Rejected for v1. It requires a consumer endpoint
  registry, outbound delivery workers, a second versioned delivery contract,
  and broker-owned pacing against slow consumers. Push remains possible later
  as an additive adapter that claims on behalf of a consumer.
- **Plain fast polling.** Simpler broker, but it trades higher latency for
  frequent empty queries at the consumer's poll rate. Long-polling with
  in-process wakeup removes the churn without adding a polling loop.
- **Persistent connection (WebSocket) for deliveries.** Rejected: a custom wire
  protocol is a v1 non-goal and HTTP application APIs are REST only.
- **Off-the-shelf broker (NATS, Kafka, RabbitMQ).** Prohibited by the
  architecture: the broker is a custom Elixir/OTP service (§0, decision 5).
- **Snapshotting the event payload onto the dead-letter row** to decouple
  dead-letter replay from event-log retention. Rejected: it duplicates every
  dead event's payload. Dependency-aware retention keeps the event alive as
  long as any delivery needs it, with one copy.
- **Automatic backfill for new subscriptions.** Rejected for v1: fan-out is a
  publish-time operation; replaying history to new consumers needs an explicit
  cursor/window design and its own decision.
- **`FOR UPDATE SKIP LOCKED` claiming instead of the subscription-row lock.**
  Deferred: the row lock keeps per-aggregate ordering simple and correct in one
  place, and the partial unique index already enforces the invariant at the
  database level. Revisit with contention measurements.
- **`LISTEN/NOTIFY` as the wakeup mechanism now.** Deferred: the broker is
  single-node, so an in-process waiter registry is sufficient and simpler;
  correctness never depends on wakeups because of the fallback sweep.
