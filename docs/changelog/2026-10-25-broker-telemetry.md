---
date: 2026-10-25
type: feat
scope: services
summary: Add telemetry emission on the broker main paths
breaking: false
adr: "0008"
contracts: -
---

# Add telemetry emission on the broker main paths

## Change

- Added `AsnEventBroker.Telemetry`: `:telemetry` events under
  `[:asn_event_broker, ...]` for accepted/rejected publishes (with event type
  and outcome, or rejection reason), claims (count including empty claims for
  the empty-claim rate), acknowledgements, dead-lettering, expired leases,
  and retention purges. Payloads and tokens are never included in
  measurements or metadata (ADR 0008 §11).
- Instrumented `Publishing`, `Delivery`, `Acknowledgements`, `LeaseReaper`,
  and `Retention` with the emission calls.
- Integration tests attach a handler and assert the published, rejected, and
  claim events with their measurements and metadata.

## Why

ADR 0008 §11 requires telemetry from day one (oldest pending age, lag, dead
count, lease-expiry rate, empty-claim rate, publish duplicates/conflicts);
these events are the raw signals metric handlers aggregate.

## Verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test` — run; 60/60 pass.

## Follow-ups

- Metric exposition (Prometheus text endpoint or similar) is a deployment
  concern, not part of the ADR; handlers attach externally.
