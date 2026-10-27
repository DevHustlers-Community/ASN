---
date: 2026-10-26
type: feat
scope: repo
summary: Add broker metrics exposition and the cross-service e2e harness; fix strict-mode CI warnings
breaking: false
adr: "0008"
contracts: openapi/event-broker-api.yaml
---

# Add broker metrics, the cross-service e2e harness, and CI strictness fixes

## Change

- Added `AsnEventBroker.Web.Metrics` and `GET /metrics` (unauthenticated, like
  health): Prometheus text exposition with counters aggregated from the
  broker's own telemetry events (publish accepted/rejected, acks,
  dead-lettering, lease expiry, retention purges) and scrape-time gauges
  (pending/leased/dead depths, oldest pending age) — completing ADR 0008 §11.
  `/metrics` is documented in the OpenAPI contract.
- Added `tests/e2e/broker-relay.sh`: the cross-service end-to-end — migrates
  both databases, boots the broker live, issues a real credential through the
  admin API, records a chat outbox row, runs the relay, claims and
  acknowledges the delivery with an intact envelope, and asserts the metrics
  trail. It resets its own state and picks a random port, and verifies the
  responding broker is its own process (a stale broker from an interrupted
  run cannot squat the port or answer readiness). Documented in
  `tests/README.md`.
- Fixed the failing Broker CI workflow: `mix test --warnings-as-errors`
  aborted after a fully passing suite because warnings were raised while
  compiling test files (an unused function parameter and an unused module
  attribute); both are fixed and the strict flag now passes locally.
- Relay HTTP fixes surfaced by the e2e: `:httpc` validates header fields as
  charlists (binaries fail with `{:headers_error, :invalid_field}`), and
  `:inets`/`:ssl` joined the chat service's extra applications. The broker's
  HTTP port is now wired from the long-reserved `EVENT_BROKER_PORT` via
  runtime config; relay retry warnings include the transport reason.

## Why

Metrics exposition and the e2e loop were the last two v1 broker surfaces; the
CI failure was invisible locally because the local verify loop ran
`mix test` without the strict flag that CI uses.

## Verification

- `tests/e2e/broker-relay.sh` — run; E2E PASS
  (chat outbox -> relay -> broker -> claim -> ack -> metrics).
- `mix test --warnings-as-errors` — broker 70/70 and chat 6/6.
- `python3 scripts/ci/check-links.py` and `check-changelog.py --all` — pass.

## Follow-ups

- Broker v1 surfaces are complete; deferred optimizations (LISTEN/NOTIFY,
  SKIP LOCKED, event partitioning) stay measurement-gated per ADR 0008.
