---
date: 2026-10-25
type: chore
scope: repo
summary: Add the broker CI workflow, verify script, and sync documentation with the implemented core
breaking: false
adr: "0008"
contracts: -
---

# Add broker CI/CD and sync documentation with the implemented core

## Change

- Added `.github/workflows/broker.yml`: the event-broker CI gate — disposable
  PostgreSQL 18.6 service container, service roles and databases bootstrapped
  from `infrastructure/postgres/init/01-create-databases.sh`, cached deps and
  build, then `mix ecto.create/migrate`, `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, and `mix test`. Path-triggered on the
  broker, postgres bootstrap, compose, and the workflow itself.
- Added `scripts/dev/broker-verify.sh` (executable): one-command local
  verification loop — compose PostgreSQL, wait for health, deps, migrate,
  format, compile, test.
- Synced documentation with the implemented core: `.github/README.md` and
  `scripts/README.md` list the new artifacts and corrected status; the broker
  README status now reflects the implemented delivery core (publish/claim/
  ack/reaper as library functions, HTTP edge and auth still pending) with an
  expanded code map; the broker CODE_MAP transport boundary notes the
  contract-first OpenAPI step for the adapter.
- Marked phases 1–3 and the CI phase complete in the private session notes.

## Why

The broker now has a runnable, tested core; CI must gate it on every change,
and the service docs must not describe the implemented machinery as missing.

## Verification

- `bash -n scripts/dev/broker-verify.sh` — syntax pass; the script was run
  end-to-end locally and finished with 38/38 tests passing.
- `python3 scripts/ci/check-links.py` and
  `python3 scripts/ci/check-changelog.py --all` — run; pass.

## Follow-ups

- Dead-letter admin actions with the audit log (phase 4), retention
  (phase 5), OpenAPI contract then the Plug/Bandit edge and auth (phase 6).
