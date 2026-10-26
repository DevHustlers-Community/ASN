---
date: 2026-10-26
type: test
scope: services
summary: Add StreamData property tests for validation, claim ordering, and concurrent leasing
breaking: false
adr: "0008"
contracts: -
---

# Add property-based concurrency tests

## Change

- Added `stream_data` as a test dependency and
  `test/property/property_test.exs` with three properties (external review
  recommendation for the claim paths):
  - valid envelopes with arbitrary JSON-safe payloads always validate, and
    the canonical content hash is deterministic across validations;
  - N versions of one aggregate are leased strictly in version order, one
    ack at a time, ending with an empty claim;
  - 2–6 concurrent claimers lease at most one delivery per aggregate, the
    one-lease-per-aggregate invariant, on real PostgreSQL through the
    sandbox.

## Why

The claim machinery is the concurrency-critical core; randomized properties
cover interleavings that hand-written tests do not reach.

## Verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test` — run; 63 pass (3 properties, 60 tests).

## Follow-ups

- Extend the property suite to fan-out eligibility and retention
  interactions when those paths grow.
