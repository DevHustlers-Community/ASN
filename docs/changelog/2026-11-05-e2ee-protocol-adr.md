---
date: 2026-11-05
type: docs
scope: decisions
summary: Record ADR 0007 selecting MLS (RFC 9420) as the target E2EE protocol
breaking: false
adr: "0007"
contracts: -
---

# Record ADR 0007 selecting MLS (RFC 9420) as the target E2EE protocol

## Change

- Added `docs/decisions/0007-e2ee-protocol-selection.md` as a proposed ADR.
  It selects MLS (RFC 9420) for direct and community conversations, defines
  Chat as the MLS Delivery Service using `conversations.last_seq` as the
  canonical order, and keeps every payload opaque.
- Recorded the schema impact: `conversations.crypto_protocol = 'mls-1.0'`,
  `crypto_state_version` as the epoch, `messages.payload_kind = 'control'` for
  handshake messages, a nullable `messages.crypto_epoch`, and a new
  `device_key_packages` table instead of overloading `device_prekeys`.
- Added a client-library gate. The ADR does not select OpenMLS, ts-mls, or the
  OpenE2EE SDK; it defines the criteria a library must meet before the first
  production E2EE release.
- Updated `docs/decisions/README.md`: 0007 is now a recorded proposed ADR, not a
  planned one.

## Why

The architecture blocks protocol-specific schema work until the E2EE protocol
direction is recorded (architecture §0.12, §9.6). The comparison had to cover
group post-compromise security, membership removal, multi-device behavior,
asynchronous delivery, React Native and web library availability, licensing,
and the post-quantum roadmap.

MLS was selected because sender-key groups do not provide the group
post-compromise security or clean removal semantics that community channels
need, and because the official Signal implementation is explicitly unsupported
outside Signal with no official React Native or web build. The ADR records the
client-library risk instead of hiding it: no candidate is both
production-grade and available on React Native and the web today.

## Verification

- Read the cited primary sources: RFC 9420 (§1, §3, §5.3.3, §14, §16.6, §16.9,
  §16.10), the Sesame specification (revision 2), the Double Ratchet
  specification (revision 4), the PQXDH specification and blog post, and the
  `draft-ietf-mls-pq-ciphersuites-07` datatracker page.
- Checked the library metadata used in the comparison: libsignal
  `@signalapp/libsignal-client` 0.106.1 (AGPL-3.0-only, Node native add-on,
  "Use outside of Signal is unsupported"), OpenMLS 0.9.0 (MIT, Rust, CI builds
  but does not test Android/iOS/WASM), ts-mls 1.6.4 (MIT, pure TypeScript,
  explicitly unaudited), and the OpenE2EE SDK 14.0.0 (MIT/Apache-2.0, pure
  TypeScript, "not audited by any independent firm").
- `python3 scripts/ci/check-links.py` — passed.
- `python3 scripts/ci/check-changelog.py --all` — passed.

No code, migrations, OpenAPI contracts, or event schemas were changed, so no
service test suite was run.

## Follow-ups

- Review and accept ADR 0007. The client-library gate remains open.
- ADR 0014 must define who may send Commits in community channels and who
  triggers the Remove Commit after a block or ban.
- Open decisions 8, 9, 10, and 13 still need their own records.
