---
date: 2026-11-04
type: chore
scope: ci
summary: Add a CI workflow for the chat service
breaking: false
adr: -
contracts: -
---

# Add a CI workflow for the chat service

## Change

- Added `.github/workflows/chat.yml`, mirroring `broker.yml`:
  - triggers on `pull_request` and on pushes to `main`, filtered to
    `services/chat-service/**`, `infrastructure/postgres/**`, `compose.yaml`,
    `.tool-versions`, and the workflow file itself;
  - PostgreSQL 18.6 service container with a `pg_isready` health check;
  - `infrastructure/postgres/init/01-create-databases.sh` creates the
    `asn_chat` role and the `chat_db` / `chat_db_test` databases;
  - `erlef/setup-beam@v1` pins Elixir 1.20.4 / OTP 29.1.2 from
    `.tool-versions`;
  - `actions/cache@v4` caches `deps` and `_build` keyed on
    `services/chat-service/mix.lock`;
  - `mix deps.get`, then `mix ecto.create`, `mix ecto.migrate`,
    `mix format --check-formatted`, `mix compile --warnings-as-errors`, and
    `mix test --warnings-as-errors`.
- Added `permissions: contents: read` and a per-ref `concurrency` group, so the
  new workflow follows the hardening the other workflows already use.
- [`/.github/README.md`](../../.github/README.md): listed the chat workflow and
  updated the status line.

## Why

Issue #24. `services/chat-service` had no CI at all: `broker.yml` only triggers
on `services/event-broker/**`, so a chat-only pull request ran neither a build
nor a test. Chat is not a stub — it has the outbox relay, broker publishing,
and the E2EE scaffolding, and its `test` alias already provisions
`chat_db_test` and migrates it. A compile break, a warnings regression, or a
failing chat test could merge green.

## Verification

- `python3 -c "yaml.safe_load(...)"` — the workflow parses; six steps in the
  `chat` job.
- Local run of the same command set against PostgreSQL 18.6
  (`asn-postgres-1` healthy), in `services/chat-service`:
  - `mix deps.get` — all dependencies fetched;
  - `mix ecto.create` — database already exists (exit 0);
  - `mix ecto.migrate` — migrations up;
  - `mix format --check-formatted` — exit 0;
  - `mix compile --warnings-as-errors` — exit 0;
  - `mix test --warnings-as-errors` — 6 passed.
- `python3 scripts/ci/check-changelog.py --all`, `python3
  scripts/ci/check-links.py` — passed.
- CI, pull request #33: `chat` job green in 59 s; `Change records and links`
  green.
- Negative test, scratch pull request #34 (one deliberately failing chat test,
  no changelog record): the `chat` job triggered from the
  `services/chat-service/**` path filter and failed at the test step —
  `1) test deliberately fails to prove the chat workflow goes red`,
  `Result: 6/7 passed`. The scratch pull request and branch were deleted after
  the run.
- Cache restore, second execution of the same run (`gh run rerun`): the
  `Cache deps and build` step logged
  `Cache hit for: chat-mix-Linux-3ec837f7…` and
  `Cache restored from key: chat-mix-Linux-3ec837f7…`, and the post step did
  not save a duplicate.

## Follow-ups

- The cross-service e2e in CI is a separate issue (#25).
