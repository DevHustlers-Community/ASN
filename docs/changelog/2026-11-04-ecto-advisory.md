---
date: 2026-11-04
type: fix
scope: security
summary: Update Ecto to 3.14.3 for EEF-CVE-2026-118391 in both Elixir services
breaking: false
adr: -
contracts: -
---

# Update Ecto to 3.14.3 for EEF-CVE-2026-118391

## Change

- [`services/event-broker/mix.lock`](../../services/event-broker/mix.lock) and
  [`services/chat-service/mix.lock`](../../services/chat-service/mix.lock):
  update `ecto` from 3.14.2 to 3.14.3. Both `mix.exs` files already allow
  `~> 3.14`, so only the lockfiles change.

## Why

`mix hex.audit` reports `EEF-CVE-2026-118391` (HIGH) on Ecto 3.14.2:
unbounded query-cache growth from interpolated JSON paths and splice lists.
Ecto 3.14.3, released on 2026-11-04, resolves it. The advisory was invisible to
CI because `mix hex.audit` exits 0 even while printing findings; #23 tracks the
strict gate.

## Verification

- `mix hex.audit` in `services/event-broker`: no retired or security advisory
  packages.
- `mix hex.audit` in `services/chat-service`: no retired or security advisory
  packages.
- `mix format --check-formatted` and `mix compile --warnings-as-errors`: pass in
  both services.
- `mix test` in `services/event-broker`: 103 passed (3 properties, 100 tests).
- `mix test` in `services/chat-service`: 6 passed.
- Local PostgreSQL 18.6 via `docker compose up -d postgres`; both suites used
  their `*_TEST_DATABASE_URL` defaults.

## Follow-ups

- #23 can add the strict `mix hex.audit` gate once this lands; the remaining
  piece is the workflow and the non-zero exit handling.
- The web tree is clean under `bun audit` after #57.
