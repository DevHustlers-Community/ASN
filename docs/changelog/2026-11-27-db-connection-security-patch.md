---
date: 2026-11-27
type: security
scope: deps
summary: Patch db_connection 2.10.3 security advisory in Chat and Broker
breaking: false
adr: -
contracts: -
---

# Patch db_connection security advisory

## Change

- Upgraded the transitive `db_connection` dependency from 2.10.2 to 2.10.3 in
  both Elixir service lockfiles.
- Addressed GHSA-gmmq-fw75-wq46 / CVE-2026-133555 without changing application
  code or service dependency constraints.

## Why

`mix hex.audit` reported a high-severity advisory for `db_connection` 2.10.2 in
both services. Version 2.10.3 is the patched release.

## Verification

- `mix deps.update db_connection` in Chat and Broker upgraded only
  `db_connection`.
- `mix format --check-formatted` and `mix compile --warnings-as-errors` — clean
  in both services.
- Chat `mix test` — 151 passed.
- Broker `mix test` — 109 passed, including 3 properties.
- `mix hex.audit` — no retired or security advisory packages in either service.
