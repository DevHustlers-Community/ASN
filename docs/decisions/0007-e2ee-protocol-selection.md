# 0007 - E2EE protocol selection: MLS (RFC 9420)

- Status: proposed
- Date: 2026-11-05
- Supersedes: -

## Context

ASN targets end-to-end encryption for every chat conversation, including direct
chats and community channels (architecture §0.11). The server stores and routes
opaque envelopes and must never hold message plaintext, private identity keys,
or session secrets. The architecture already fixes the opaque envelope contract
and keeps the persisted schema protocol-neutral until this decision is recorded
(§0.12, §1.9, §3.5-§3.10).

Requirements that constrain the choice:

| Requirement | Detail |
|---|---|
| Direct chat | Two users, each with multiple devices. |
| Community chat | Many members, membership changes, removals and bans. |
| Multi-device | One cryptographic identity per installed client; device linking and revocation. |
| Asynchronous delivery | Recipients may be offline; the server stores ciphertext until sync. |
| Clients | React Native (Android/iOS) and React web. Web parity may lag, but must not silently downgrade (ADR 0010). |
| Server-blind | No plaintext, no private keys, no server-side content inspection. |
| Removal semantics | A removed or banned member must not decrypt future messages, not merely stop receiving them. |
| Licensing | The repository is AGPL-3.0; dependencies must be compatible. |
| Post-quantum | A migration path is required; harvest-now-decrypt-later is a real risk for long-lived chats. |
| No custom crypto | Do not invent a protocol or ship custom cryptography (§0.12). |

This decision blocks the protocol-specific parts of the schema: the meaning of
`device_prekeys`, `chat_devices.identity_key_public`, the
`conversations.crypto_*` fields, the handshake-message shape in `messages` and
`message_payloads`, group key rotation (open decision 9), device verification
(open decision 8), backup/restore (open decision 10), and the approved metadata
list (open decision 13). It does not block protocol-neutral tables such as
`chat_users`, `chat_block_edges`, or `processed_events`.

## Options considered

### A. Signal/Sesame

X3DH/PQXDH for asynchronous session establishment, the Double Ratchet (or the
newer Triple Ratchet) for 1:1 ratcheting, Sesame for multi-device session
management, and Sender Keys for groups.

### B. MLS (RFC 9420)

A tree-based asynchronous group key agreement. A direct chat is a two-member
group; a community channel is an n-member group. Membership changes are
Proposals and Commits; a new device joins through a KeyPackage and a Welcome.

### C. Hybrid

Signal/Sesame for direct chats and MLS for groups. Rejected as the default:
two protocols, two identity/key infrastructures, two client libraries, and
cross-protocol membership semantics. It remains a fallback only if the MLS
client gate below fails.

## Evaluation

### Comparison summary

| Criterion | Signal/Sesame | MLS (RFC 9420) | Weight |
|---|---|---|---|
| 1:1 forward secrecy and PCS | Strong (Double/Triple Ratchet) | Strong (two-member group) | Both acceptable |
| Group PCS | Weak (sender keys; RFC 9420 §1) | Strong (tree; log group size) | High |
| Membership removal | O(n) sender-key rotation; weak | Remove Commit rotates group secrets | High |
| Multi-device | Sesame, proven in Signal | One leaf per device; more handshakes | Medium |
| Asynchronous first message | X3DH/PQXDH, mature | KeyPackage + Welcome, one extra round trip | Medium |
| React Native library | Native bridge around Java/Swift | No production binding; ts-mls is pure TS but unaudited | Decisive for v1 |
| Web library | No official WASM build | OpenMLS WASM experimental; ts-mls pure TS | High for web parity |
| License | AGPL-3.0-only, compatible | MIT | Not a blocker |
| Post-quantum | PQXDH and Triple Ratchet implemented | Draft-07, not final | Medium |
| Server complexity | Lower | Delivery Service, epochs, Commit conflicts | Medium |

The React Native row is decisive for the first release; the web row is decisive
for web parity. The protocol choice is driven by group security and removal
semantics; the library choice is driven by client viability.

### Group confidentiality and post-compromise security

RFC 9420 §1 describes the problem with sender keys directly: it is difficult to
achieve post-compromise security with sender keys, key updates scale as the
square of the group size, and an adversary who learns a sender key can often
eavesdrop indefinitely and passively on that member's messages. Generating a new
sender key restores security for that sender but costs work linear in the group
size. MLS derives and updates group keys with costs that scale as the logarithm
of the group size, and RFC 9420 §16.6 defines forward secrecy between epochs and
post-compromise security when members update their leaf keys and the group
processes the Commit.

This matters for ASN because community channels are a first-class product
surface, and because a ban or removal must stop future decryption. With MLS, a
Remove Commit changes the group secrets for the next epoch; the removed device
cannot decrypt later messages even if it obtains them. With sender keys, every
remaining member must rotate and redistribute their sender key; one member who
fails to do so leaves their messages readable to the removed device.

### Multi-device

Sesame (revision 2, 2017-04-14) is explicitly designed for asynchronous,
multi-device session management, and it is proven in Signal. MLS handles
multi-device differently: every device is a separate leaf in the group. RFC 9420
§5.3.3 notes that multiple devices belonging to one user may present the same
application-layer identifier, so the application must not assume that a
credential uniquely identifies a device. This is workable, but it means a direct
chat between two users with three devices each is a six-leaf group, and every
device addition or removal is a Commit.

Both models are viable. MLS has the advantage that device removal is
cryptographically effective for the whole conversation, not just for one
sender's key.

### Asynchronous delivery and ordering

MLS assumes an Authentication Service and a Delivery Service (RFC 9420 §3). The
Delivery Service is not trusted for confidentiality, but it must reliably
deliver messages; a compromised Delivery Service can delay, drop, or selectively
withhold messages (§16.9). RFC 9420 §14 requires the application to define how
conflicting Commits for the same epoch are resolved.

Chat already serializes messages per conversation through `conversations.last_seq`
(architecture §3.5, §3.9). That sequence is a natural Delivery Service order:
the first accepted Commit for an epoch is canonical, and later Commits for the
same epoch are rejected with a conflict error. This is a server-side coordination
rule, not a cryptographic trust claim: clients still validate every Commit.

### Client libraries

This is the decisive constraint. The protocol is only usable if a maintained,
reviewable implementation runs on React Native Android/iOS, and on the web when
web E2EE ships (ADR 0010).

| Candidate | Protocol | License | Runtime support | Maturity | Audit |
|---|---|---|---|---|---|
| [`@signalapp/libsignal-client`](https://www.npmjs.com/package/@signalapp/libsignal-client) 0.106.1 | Signal (X3DH/PQXDH, Double/Triple Ratchet, Sesame, Sender Keys) | AGPL-3.0-only | Official Java, Swift, and TypeScript (Node native add-on) libraries | Production at Signal scale; README says "Use outside of Signal is unsupported" | No audit claim found in the repository README |
| [OpenMLS](https://github.com/openmls/openmls) 0.9.0 | MLS RFC 9420 | MIT | Rust; CI builds but does not test `aarch64-linux-android`, `aarch64-apple-ios`, or `wasm32-unknown-unknown`; `openmls-wasm` is an experiment | Active, about 1.1k stars; PQ cipher suites behind a draft feature flag | No published third-party audit found in the repository README or security policy |
| [ts-mls](https://github.com/LukaJCB/ts-mls) 1.6.4 | MLS RFC 9420 | MIT | Pure TypeScript (browser, Node, React Native via Hermes) | Young (first published 2025); implements ML-KEM and X-Wing suites with provisional IDs | README: "has not undergone a formal security audit" |
| [`@open-e2ee/signal-protocol-sdk`](https://www.npmjs.com/package/@open-e2ee/signal-protocol-sdk) 14.0.0 | Versioned Signal profile, not wire-compatible with libsignal | MIT OR Apache-2.0 | Pure TypeScript; Expo, React Native, browser, Node | Young (first published 2026-07); PQXDH and ML-KEM Braid | README: "not audited by any independent firm" |

Key findings:

- libsignal is the most battle-tested implementation, and its AGPL-3.0 license is
  compatible with this AGPL-3.0 repository. The problem is integration and
  support: the official wrappers are Java, Swift, and a Node native add-on. A
  React Native client would need native modules around the Java and Swift
  libraries, and the web client would need a WASM build that libsignal does not
  officially ship. "Use outside of Signal is unsupported" also means API changes
  can land without notice.
- OpenMLS is a serious Rust implementation with a permissive license, but it does
  not ship React Native or web bindings. The project would own a UniFFI/JNI
  binding layer for mobile and a WASM build for web. OpenMLS builds the mobile
  and WASM targets in CI but does not test them, and `openmls-wasm` describes
  itself as an experiment.
- ts-mls is the only candidate that runs as pure TypeScript on React Native and
  the web without a native bridge, and it already implements PQ cipher suites.
  It is also young and explicitly unaudited, and its PQ cipher-suite identifiers
  are provisional until the IETF draft is final.
- The OpenE2EE SDK is the closest match for React Native and web, including
  device-local storage adapters and PQ by default, but it is new, unaudited, and
  not wire-compatible with Signal or libsignal. Choosing it is a separate trust
  decision, not just a protocol decision.

No candidate is both production-grade and available on React Native and the web
today. That is the central risk of this ADR, and it is why the library selection
is gated rather than assumed.

### License and maintenance

- libsignal: AGPL-3.0-only. Compatible with ASN's AGPL-3.0 license. The
  maintenance risk is the explicit lack of support outside Signal.
- OpenMLS: MIT. Actively maintained by Phoenix R&D and CE Labs.
- ts-mls: MIT. Small project; single-maintainer risk is not documented either
  way.
- OpenE2EE: MIT/Apache-2.0. Very young; the project publishes an assurance
  methodology but states that it is not independently audited.

### Post-quantum

- Signal: PQXDH (2023-09-19) augments X3DH with a post-quantum KEM, and the
  Double Ratchet revision 4 (2025-11-04) specifies the Sparse Post-Quantum
  Ratchet and the Triple Ratchet. The libsignal repository contains `pqxdh.rs`,
  a `kem/` module, and `triple_ratchet.rs`, which indicates the implementation is
  present in the codebase.
- MLS: ML-KEM and hybrid cipher suites are specified in
  `draft-ietf-mls-pq-ciphersuites-07` (2026-11-01, publication requested).
  OpenMLS exposes them behind a `draft-ietf-mls-pq-ciphersuites` feature flag.
  ts-mls implements ML-KEM and X-Wing suites with provisional identifiers
  (`0xf007`-`0xf012`), which must not be treated as stable interoperability
  points before the draft is final.

Signal has specified and implemented post-quantum session establishment and
ratcheting; MLS has a credible standards-track path, but its PQ suites are not
final. This ADR records that gap rather than hiding it.

### Server complexity and schema fit

MLS adds server work: KeyPackage distribution, Welcome delivery, Commit
serialization per epoch, and epoch-aware conflict handling. Chat already has the
durable per-conversation log and sequence needed to act as the Delivery Service.
The existing schema is close to MLS-shaped:

- `messages.payload_mode = 'shared'` fits one group ciphertext per epoch;
  `'per_device'` fits Welcome messages and device-specific control payloads.
- `messages.payload_kind = 'control'` fits Proposals, Commits, and Welcomes.
- `conversations.crypto_protocol` and `crypto_state_version` fit the protocol
  identifier and epoch.
- `message_payloads` already stores opaque bytes with a nullable
  `recipient_device_id`.

The main mismatch is `device_prekeys`, which is shaped for Signal-style prekey
bundles. MLS needs a KeyPackage bundle with a ciphersuite, an expiry, and
one-time consumption semantics. Overloading `device_prekeys.kind` would blur two
different protocols; a dedicated `device_key_packages` table is clearer.

## Decision

1. **MLS (RFC 9420) is the target E2EE protocol for ASN chat.** It covers direct
   conversations (two-member groups) and community conversations (n-member
   groups). ASN does not invent a protocol and does not ship custom
   cryptography.
2. **Each device is an MLS leaf.** A device has its own signature key pair and
   its own KeyPackage. Multiple devices may share the user's application-level
   identity, but the application must not treat a credential as a unique device
   identifier (RFC 9420 §5.3.3).
3. **Device lifecycle is a group operation.** Adding a device is an Add proposal
   plus a Commit plus a Welcome to the new device. Removing a device is a Remove
   proposal plus a Commit. Removing a member rotates the group secrets for the
   next epoch.
4. **Chat acts as the MLS Delivery Service.** `conversations.last_seq` is the
   canonical order for handshake and application messages. The first accepted
   Commit for an epoch is canonical; a second Commit for the same epoch is
   rejected with a conflict error, and the sender must re-sync and retry on the
   new epoch. Chat does not validate cryptography; clients validate every
   Commit and reject stale epochs.
5. **The Authentication Service is Auth0 identity plus Chat's device registry.**
   Chat authenticates device registration and publishes the binding between the
   authenticated user and the device's signature key. A compromised Chat server
   can assert a binding (RFC 9420 §16.10), so device key changes are auditable,
   visible to clients, and subject to verification (open decision 8).
6. **Chat stores only opaque protocol material.** KeyPackages, Welcomes,
   Proposals, Commits, and application messages are byte strings. Chat never
   stores private keys, epoch secrets, or plaintext.
7. **Protocol identifiers:** in production,
   `conversations.crypto_protocol = 'mls-1.0'` and
   `conversations.crypto_protocol_version = 1`. `crypto_state_version` mirrors
   the last accepted MLS epoch. It is updated from the control message's
   declared epoch after the Commit is accepted; it is a coordination counter,
   not a cryptographic trust anchor. Until the client library gate passes, the
   only protocol used in development is `dev-opaque-v1`, which keeps the same
   envelope shape.
8. **KeyPackage storage is a new `device_key_packages` table**, not a reuse of
   `device_prekeys`. The table stores the opaque KeyPackage bundle, ciphersuite,
   creation/expiry timestamps, an optional `last_resort` flag, and a
   `consumed_at` timestamp for one-time claiming. Claiming is atomic so a
   KeyPackage is never handed to two initiators.
9. **The client library is not selected by this ADR.** Library selection is a
   client-phase gate with explicit pass criteria (below). The backend may build
   MLS-shaped, opaque storage before the gate; it must not claim production E2EE
   until the gate passes.
10. **Post-quantum:** v1 uses a classic MLS ciphersuite. The hybrid ML-KEM
    ciphersuite is a follow-up when the IETF draft is final, the chosen library
    supports it without provisional identifiers, and cross-client test vectors
    pass. This is a recorded limitation, not a silent omission.
11. **Signal/Sesame is not selected as the primary protocol.** It remains the
    documented fallback if the MLS client gate fails for both React Native and
    the web. Adopting it requires a superseding ADR, not an implicit switch.

### Client library gate

A library is acceptable for the first production E2EE release only if all of the
following hold:

- It implements RFC 9420 and passes the official MLS test vectors from
  [`mlswg/mls-implementations`](https://github.com/mlswg/mls-implementations/tree/main/test-vectors),
  or documents every deviation with a reviewed justification.
- It runs on the platforms in scope for that release (React Native Android and
  iOS; web when web E2EE ships) without custom cryptography. Pure TypeScript on
  Hermes is acceptable; a native binding is acceptable only if it is maintained
  and buildable in CI.
- It supports KeyPackage creation/consumption, Welcome processing, Add/Remove,
  Commit ordering, and epoch re-sync after missed messages.
- It has a maintenance plan: recent releases, issue triage, and a security
  contact.
- It has an independent security audit, or the project funds one before
  production. An unaudited library may be used for a spike, not for production.
- It documents its post-quantum roadmap and does not require provisional
  ciphersuite identifiers in production.

## Consequences

### Positive

- One protocol covers direct chats and community channels; no hybrid key
  infrastructure.
- Group post-compromise security and cryptographic removal align with the
  ban/block/removal requirements: a removed device cannot decrypt the next
  epoch.
- The per-conversation sequence already provides the Delivery Service order MLS
  needs.
- The protocol is an open IETF standard with MIT-licensed implementations, not a
  vendor-controlled stack.
- The opaque envelope and protocol-neutral schema remain valid; the migration is
  additive.

### Negative and risks

- **Client library risk is the largest risk.** No candidate is both
  production-grade and available on React Native and the web today. The gate
  above is a real blocker, not a formality.
- **Direct-chat handshake overhead.** A first message requires fetching the
  recipient's KeyPackages and delivering a Welcome before application messages
  can flow. This adds a round trip and a control message to every new direct
  conversation.
- **Commit conflicts and denial of service.** A malicious member can send
  invalid Commits or spam Proposals. Clients reject invalid Commits, but the
  server must rate-limit and authorize who may commit in community channels
  (ADR 0014).
- **Block and ban enforcement must cover every entry point.** A blocked or
  banned user who can still claim a KeyPackage or register a new device could
  establish a fresh MLS session. The policy in ADR 0014 must apply to KeyPackage
  upload/claim, conversation join, device registration, and send, not only to
  application messages.
- **Chat is the Authentication Service.** A compromised Chat server can bind a
  signature key to a user and impersonate them (RFC 9420 §16.10). This is
  inherent to the AS role; key transparency or cross-signing would reduce it,
  but is not in scope for v1.
- **The server cannot cryptographically remove a banned user.** Chat can stop
  routing immediately, but only an authorized client can produce the Remove
  Commit that rotates the group secrets. If no client performs it, the banned
  user retains the old epoch secrets; the server's routing block is the
  real-time control, and cryptographic removal is defense in depth. ADR 0014
  must define who triggers the Commit and what happens if they do not.
- **No pre-join history by default.** A new device or member gets the current
  epoch, not past messages. Sharing history requires a separate encrypted
  client-to-client design (open decision 9).
- **Backup and restore interact with epochs.** Restoring an old backup can leave
  a client at an old epoch; it must replay handshake messages from the Delivery
  Service, and if it missed a Remove it may need to rejoin with a new KeyPackage
  and Welcome, losing history. Open decision 10 must account for this.
- **Post-quantum gap in v1.** Classic MLS is not harvest-now-decrypt-later
  resistant. The hybrid suite is a follow-up; if PQ resistance is a launch
  requirement, this decision must be revisited.
- **Metadata.** KeyPackage fetches reveal who intends to message whom; group
  membership, timing, sizes, and receipts remain server-visible. This belongs in
  the approved metadata list (open decision 13).
- **Larger control messages.** Welcomes and Commits grow with group size and
  tree state; storage and bandwidth budgets must be measured, especially for
  large community channels.

## Schema impact

| Table | Change | Blocked by this ADR? |
|---|---|---|
| `conversations` | Set `crypto_protocol = 'mls-1.0'`; use `crypto_state_version` as the epoch. No structural change. | No; column already exists. |
| `messages` | Use `payload_kind = 'control'` for handshake messages; `payload_mode = 'shared'` for Commit/Proposal and `'per_device'` for Welcome. Add nullable `crypto_epoch` for control-message conflict detection. | Partially; `crypto_epoch` is a new column. |
| `message_payloads` | No structural change; stores opaque MLS bytes. | No. |
| `chat_devices` | `identity_key_public` carries the MLS signature public key; `registration_id` is unused for MLS and stays nullable. `identity_key_fingerprint` is the client-derived verification fingerprint. | No structural change; semantics change. |
| `device_prekeys` | Not used for MLS. Keep the table out of the MLS path. | No; do not migrate it for MLS. |
| `device_key_packages` | New table: `id`, `device_id`, `ciphersuite`, `key_package` (bytea), `last_resort`, `created_at`, `expires_at`, `consumed_at`. Partial index for unconsumed packages; atomic claim. | Yes; add after the library gate confirms the KeyPackage shape. |

The `messages.crypto_epoch` column is the only structural change to an existing
planned table. It is nullable and only populated for `payload_kind = 'control'`,
so application messages keep the existing shape.

## Alternatives considered

- **Signal/Sesame as the primary protocol.** Rejected because sender-key groups
  do not provide the group post-compromise security or the clean removal
  semantics ASN needs for community channels, and because the official
  implementation is explicitly unsupported outside Signal with no official
  React Native or web build. It remains the fallback if the MLS client gate
  fails.
- **Hybrid Signal for 1:1 and MLS for groups.** Rejected for the first release:
  two protocols, two identity/key systems, two libraries, and ambiguous
  membership semantics at the boundary. Revisit only if the MLS gate fails and a
  staged migration is cheaper than a full fallback.
- **A custom protocol.** Rejected by architecture §0.12. No custom cryptography.
- **Sender Keys with a stronger rotation schedule.** Rejected because the
  fundamental post-compromise property is weaker and the operational cost grows
  with group size; a rotation schedule does not fix a leaked sender key.

## Open questions

These are deliberately not decided here:

- The exact classic ciphersuite and the hybrid PQ ciphersuite, pending library
  and test-vector results.
- Who may send Commits in community channels (owner, admins, any member), and
  how the server authorizes that without validating cryptography. This belongs
  in ADR 0014.
- The block/ban workflow: which client produces the Remove Commit, how device
  lists are fetched, and what happens when no authorized client is online. This
  belongs in ADR 0014.
- Pre-join history and device-to-device history transfer (open decision 9).
- Backup format and restore behavior across epochs (open decision 10).
- The approved server-visible metadata list (open decision 13).
- Device verification UX and identity-key change handling (open decision 8).
- KeyPackage last-resort policy and expiry.
- Maximum supported group size and the commit-size/latency budget.

## References

- RFC 9420, *The Messaging Layer Security (MLS) Protocol*:
  <https://www.rfc-editor.org/rfc/rfc9420> (cited sections: §1, §3, §5.3.3,
  §14, §16.6, §16.9, §16.10).
- Signal, *The Sesame Algorithm: Session Management for Asynchronous Message
  Encryption*, revision 2, 2017-04-14:
  <https://signal.org/docs/specifications/sesame/>.
- Signal, *The Double Ratchet Algorithm*, revision 4, 2025-11-04:
  <https://signal.org/docs/specifications/doubleratchet/>.
- Signal, *PQXDH*, 2024-01-23: <https://signal.org/docs/specifications/pqxdh/>.
- Signal blog, *Quantum Resistance and the Signal Protocol*, 2023-09-19:
  <https://signal.org/blog/pqxdh/>.
- IETF, *ML-KEM and Hybrid Cipher Suites for Messaging Layer Security*,
  `draft-ietf-mls-pq-ciphersuites-07`, 2026-11-01:
  <https://datatracker.ietf.org/doc/draft-ietf-mls-pq-ciphersuites/>.
- libsignal: <https://github.com/signalapp/libsignal>.
- OpenMLS: <https://github.com/openmls/openmls>; WASM bindings experiment:
  <https://github.com/openmls/openmls/tree/main/openmls-wasm>.
- ts-mls: <https://github.com/LukaJCB/ts-mls>.
- OpenE2EE Signal Protocol SDK:
  <https://github.com/open-e2ee/signal-protocol-js>.
- MLS test vectors:
  <https://github.com/mlswg/mls-implementations/tree/main/test-vectors>.
- Architecture: [`docs/architecture/architecture-and-schema.md`](../architecture/architecture-and-schema.md)
  §0.11-§0.12, §1.9, §3.5-§3.10, §9.6-§9.9.
