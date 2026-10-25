---
date: 2026-10-25
type: docs
scope: services
summary: Record and accept ADR 0008 (rev 3) for the broker transport and delivery contract
breaking: false
adr: "0008"
contracts: -
---

# Record and accept ADR 0008 (rev 3) for the broker transport and delivery contract

## Change

- Added `docs/decisions/0008-broker-transport-and-delivery-contract.md`
  (status: proposed). It selects HTTP claim-based pull delivery with
  long-polling (no broker-initiated outbound connections; in-process wakeup
  with a configurable fallback sweep instead of busy polling) and defines the
  v1 REST surface (`/v1/events`, subscription claims, ack/nack/extend/skip,
  dead-letter inspection and replay, admin subscription management, health).
- Revision 2 incorporated two external architecture reviews: idempotent
  publish with content integrity; unique strictly-increasing
  `aggregate_version` per aggregate; lease validity with hashed tokens and
  database-time expiry; the delivery state machine with explicit transitions
  and a terminal admin `skipped` state; deliberate head-of-line blocking per
  aggregate with admin-only replay/skip; dependency-aware retention; no
  automatic backfill for new subscriptions; paused-subscription semantics;
  claim concurrency via a short subscription-row lock plus a partial unique
  index enforcing one lease per aggregate; per-service credentials with
  rotation, expiry, revocation, event-type restrictions, and an audited admin
  surface bootstrapped from `BROKER_ADMIN_TOKEN`; a 256 KiB
  whole-request-body limit enforced at the adapter; and the telemetry
  baseline.
- Revision 3 tightened four contract details before acceptance:
  publish integrity hashes the **complete canonical envelope**
  (`content_hash`), not only the payload, so reusing an `event_id` with any
  differing effective field or publisher returns 409; the per-aggregate
  ordering guarantee extends to the producer outbox relay (publish version N,
  advance to N+1 only after N is definitively accepted, retry the same
  `event_id` on timeout, halt-and-alert on 409/422, with relay failure-path
  tests) and one event per `aggregate_version` is stated as a deliberate
  event-model constraint; ack idempotency is exact (repeat ack with the token
  of the lease that produced `delivered` succeeds; a superseded token after
  re-lease can never change state, pinned by keeping the final
  `lease_token_hash` on delivered rows); and the audit log is written in the
  same `broker_db` transaction as the admin state change it records, with
  retention (deletion policy) explicitly separated from replay availability
  (dead-letter replay only in v1; the 7-day event-log figure is a floor, not
  a replay promise).
- Numeric defaults (lease 30 s, in-flight 10 per subscription and 1 per
  aggregate, 5 attempts with exponential backoff and jitter, retention 24 h /
  7 days / 30 days, 256 KiB) are configuration, not contract.
- Updated `docs/decisions/README.md` to list ADR 0008 as recorded (proposed)
  and removed it from the planned list.
- Updated `services/event-broker/README.md` status, local development note,
  configuration notes, and related links to reference the proposed ADR.
- Updated `services/event-broker/CODE_MAP.md` transport boundary from "the
  transport decision is open" to the proposed claim-based pull selection.
- Updated `docs/architecture/architecture-and-schema.md` §9 item 3 to link
  [ADR 0008](../../docs/decisions/0008-broker-transport-and-delivery-contract.md)
  as the recorded (proposed) broker transport decision, per the ADR process
  requirement to link delivery-semantics decisions from the architecture
  document.
- Added the `BROKER_ADMIN_TOKEN` placeholder to `.env.example`; it is reserved
  for the first-boot admin credential bootstrap described in the ADR and is
  not read by the scaffold.
- Added `SSS.md` (private local session notes) to `.gitignore` so it is never
  committed or published.
- Accepted ADR 0008: status flipped from `proposed` to `accepted` after the
  review round closed and the four pre-acceptance precisions landed; the
  status references in `docs/decisions/README.md`, the architecture document
  (§9.3), the broker README, and the broker CODE_MAP were updated to match.

## Why

The architecture document (§9.3) and the agent rules require the broker
transport, lease semantics, in-flight limits, retry/backoff, retention, payload
limit, and replay authorization to be settled by an ADR before implementation.
The broker scaffold was intentionally transport-neutral until this record
existed. Consumers are a fixed set of long-lived backend services, REST is the
only permitted HTTP style, and a custom wire protocol is a v1 non-goal, which
makes claim-based pull with long-polling the lowest-risk transport that keeps a
push upgrade open as an additive edge adapter. The external reviews conditioned
acceptance on closing the retention/replay conflict, publish-integrity gaps,
ordering semantics around dead letters, lease validity rules, and subscription
and credential lifecycle. The final pre-acceptance review required four
further precisions — envelope-wide integrity hashing, an enforceable producer
relay ordering contract, exact ack idempotency, and transactionally consistent
auditing with an explicit retention/replay split — before the ADR can be
accepted, so that the implementing agent never has to invent delivery-contract
decisions.

## Verification

- `python3 scripts/ci/check-links.py` — run; see output in the session record.
- `python3 scripts/ci/check-changelog.py --all` — run; see output in the
  session record.
- No code, contract, or migration changes in this record; service compile and
  test loops were not affected and were not run.

## Follow-ups

- Review and accept (or amend) ADR 0008 revision 3; flip its status from
  `proposed` to `accepted` in the same review. Do not start the envelope
  contract or any code before the review closes and the ADR is explicitly
  accepted.
- After acceptance: land the event envelope schema as
  `contracts/events/common/event-envelope.schema.json` per the events
  contracts README, documenting publisher identity from credentials,
  aggregate-version uniqueness, envelope-wide content hashing, and the
  request-body limit in the contract.
- Implement the broker migrations (`events`, `subscriptions`, `deliveries`,
  `service_credentials`, `audit_log`) and the vertical slice
  publish → claim → ack with integration tests on real PostgreSQL, then
  retries, dead letters, retention, and the failure-path suite — including the
  relay ordering contract and superseded-lease-token cases — per the ADR.
