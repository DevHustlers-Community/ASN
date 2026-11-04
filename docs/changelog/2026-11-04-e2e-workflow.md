---
date: 2026-11-04
type: chore
scope: ci
summary: Run the cross-service broker e2e in CI
breaking: false
adr: -
contracts: -
---

# Run the cross-service broker e2e in CI

## Change

- Added `.github/workflows/e2e.yml`, separate from `broker.yml` because its
  triggers span two services:
  - triggers on `pull_request` and on pushes to `main`, filtered to
    `services/event-broker/**`, `services/chat-service/**`, `tests/e2e/**`,
    `infrastructure/postgres/**`, `compose.yaml`, `.tool-versions`, and the
    workflow file;
  - PostgreSQL 18.6 service container with a `pg_isready` health check and
    `infrastructure/postgres/init/01-create-databases.sh`;
  - `erlef/setup-beam@v1` with Elixir 1.20.4 / OTP 29.1.2;
  - the existing `broker-mix-*` and `chat-mix-*` caches, so the job reuses the
    `deps`/`_build` trees the service workflows already build;
  - `mix deps.get` in both services, then `bash tests/e2e/broker-relay.sh`;
  - `timeout-minutes: 10`, so a hung broker cannot hold the runner;
  - a failure-only step that tails `/tmp/e2e-broker.log` and
    `/tmp/e2e-relay.log`.
- Database URLs are passed through `E2E_BROKER_DATABASE_URL`,
  `E2E_BROKER_TEST_DATABASE_URL`, and `E2E_CHAT_DATABASE_URL` because the
  script's defaults use the local `change_me` password.
- [`/.github/README.md`](../../.github/README.md): listed the e2e workflow and
  updated the status line.

## Why

Issue #25. `tests/e2e/broker-relay.sh` is the only test covering the full
cross-service path — chat outbox row → relay → broker publish → claim → ack →
`/metrics` — and no workflow ran it. Neither service's unit tests exercise the
contract the two services share (envelope shape, credential scopes,
subscription routing, relay retry behavior), so that contract could break with
a green suite on both sides.

## Verification

- `bash tests/e2e/broker-relay.sh` locally against PostgreSQL 18.6
  (`asn-postgres-1` healthy): `E2E PASS: chat outbox -> relay -> broker ->
  claim -> ack -> metrics` in 13.5 s with warm `deps`/`_build`.
- The workflow YAML parses; one job with seven steps plus the failure-only log
  step.
- `python3 scripts/ci/check-changelog.py --all`, `python3
  scripts/ci/check-links.py` — passed.
- CI: see the pull request run for `e2e.yml` on this branch.

## Follow-ups

- A deliberately broken assertion on a scratch branch to confirm the job goes
  red (acceptance criterion in #25).
