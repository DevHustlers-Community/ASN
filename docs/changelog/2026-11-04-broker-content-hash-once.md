---
date: 2026-11-04
type: perf
scope: broker
summary: Compute the event content hash once per publish instead of twice
breaking: false
adr: 0008
contracts: -
---

# Compute the event content hash once per publish instead of twice

## Change

- `lib/asn_event_broker/events/event.ex`: `Event.new_from_envelope/3` now
  takes the already-computed canonical envelope hash as a required
  `content_hash:` keyword argument instead of recomputing it via
  `Envelope.content_hash/1`.
- `lib/asn_event_broker/publishing.ex`: `insert_event/4` passes the `hash`
  that `publish/2` computed at the top of the call into
  `Event.new_from_envelope/4`. The `_hash` argument is named and documented
  rather than discarded.
- `test/integration/publishing_test.exs`: new regression test asserting the
  stored `content_hash` equals an independently canonicalized SHA-256 of the
  envelope (recursively key-sorted JSON, nested maps, out-of-order keys)
  and equals `Envelope.content_hash/1` for the same envelope.

## Why

`Publishing.publish/2` computed the canonical envelope hash, then
`Event.new_from_envelope/3` recomputed it — canonical JSON (recursive key
sort plus encode) and SHA-256 ran twice per publish. At the 256 KiB payload
size in the issue this doubles the canonicalization cost.

Measured on a 262,217-byte payload (`mix run` timing, 20 iterations):
`Envelope.content_hash/1` takes ~1.48 ms; the old two-call publish path took
~2.81 ms. The fix removes ~1.3 ms of canonicalization per publish at that
size. The stored hash value is unchanged, so idempotency and conflict
semantics are unaffected.

## Verification

- `mix format --check-formatted` — exit 0.
- `mix compile --warnings-as-errors` — exit 0, no warnings.
- `mix test test/integration/publishing_test.exs test/property/property_test.exs`
  — 13 passed (10 tests, 3 properties).
- `mix test` (full suite) — 85 passed (82 tests, 3 properties), no failures.
- `python3 scripts/ci/check-changelog.py --all` — "Change records OK".
- `python3 scripts/ci/check-links.py` — "Relative documentation links OK".
- Micro-benchmark (`mix run /tmp/opencode/bench_hash.exs`, 262,217-byte
  payload, 20 iterations): single hash ~1.48 ms vs ~2.81 ms for the old
  two-call path. Not committed; artifact left in the local temp directory.

## Follow-ups

- None. The remaining `content_hash` cost is one canonicalization per
  publish, which is the integrity anchor required by the publish contract.
