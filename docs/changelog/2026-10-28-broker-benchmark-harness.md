---
date: 2026-10-28
type: chore
scope: broker
summary: Add a stdlib-only event broker benchmark harness (B1-B9)
breaking: false
adr: 0008
contracts: -
---

# Add a stdlib-only event broker benchmark harness (B1-B9)

## Change

- Added `scripts/dev/broker-load.py`: plan checks (B1), publish steady-state
  (B2), fan-out burst (B3), claim/wake latency (B4), idle parked cost (B5),
  backlog drain (B6), retention purge (B7), metrics scrape (B8), and
  authorization cost (B9).
- Added `docs/performance/README.md` and `docs/performance/broker-baseline.md`
  with safety rules, per-scenario instructions, and a results template.
- Linked the harness from `scripts/README.md` and the event broker README.

## Why

The broker has correctness coverage but no measured performance baseline.
Benchmarks come first so fixes are justified by data rather than assumption.

## Verification

- `python3 -m py_compile scripts/dev/broker-load.py` — passed.
- `python3 scripts/dev/broker-load.py --scenario b1` against local PostgreSQL
  18.6 — completed; JSON written.
- `python3 scripts/ci/check-links.py` — passed.
- Broker gates were not changed by this commit (no production code touched).

## Follow-ups

- Run B2-B9 against a live broker and record a dated baseline in
  `docs/performance/broker-baseline.md`.
