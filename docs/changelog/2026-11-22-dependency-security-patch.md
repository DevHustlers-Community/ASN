---
date: 2026-11-22
type: fix
scope: deps
summary: Patch Phoenix and Plug to clear new Hex security advisories
breaking: false
---

# Patch Phoenix and Plug for new security advisories

## Change

- Chat lockfile: `phoenix 1.8.16 -> 1.8.17`, `plug 1.20.3 -> 1.20.4`.
  Transitive resolutions moved with them: `bandit 1.14.1 -> 1.15.0`,
  `telemetry 1.4.2 -> 1.4.3`, and `websock_adapter 0.6.0 -> 0.7.2`.
- Broker lockfile: `plug 1.20.3 -> 1.20.4` and `telemetry 1.4.2 -> 1.4.3`.
- Updated the current-state version pins in `AGENTS.md`, architecture §3,
  ADR 0011 (kept the 1.8.16 baseline as history), the Chat README, and the
  development environment docs. Historical session reports and older change
  records were left untouched.

## Why

`mix hex.audit` began failing after new advisories were published:

- `phoenix 1.8.16`: `CVE-2026-128361` (HIGH, unsanitized Presence key crashes the
  tracker shard) and `CVE-2026-129344` (HIGH, client-selected V1 serializer
  crashes broadcast dispatch). Fixed in 1.8.17.
- `plug 1.20.3`: `CVE-2026-120287` (MEDIUM, multipart `:length` limit not charged
  for framing bytes, allowing memory amplification). Fixed in 1.20.4.

Both fixes are patch releases inside the existing `~> 1.8` / `~> 1.20`
constraints, so no `mix.exs` requirement changed. The affected features
(Phoenix Presence, live channels, multipart parsing) are not implemented in
these services yet, but the audit gate rejects any known advisory.

## Verification

- `mix hex.audit` for both services — no advisories
- Chat: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test` — 151 tests pass
- Broker: same checks — 105 tests pass
- `scripts/ci/check-links.py`, `scripts/ci/check-changelog.py --all`,
  `git diff --check` — OK

## Follow-ups

- Re-run the PR CI after pushing so the `Hex audit` checks turn green.
