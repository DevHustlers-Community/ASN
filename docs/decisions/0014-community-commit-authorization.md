# 0014 - Community commit authorization and post-block removal

- Status: proposed
- Date: 2026-11-06
- Supersedes: -

## Context

[ADR 0007](0007-e2ee-protocol-selection.md) selects MLS (RFC 9420) for E2EE and
makes the chat service the Delivery Service: it accepts Commits for an epoch and
declares the first accepted Commit for an epoch canonical. ADR 0007 explicitly
defers two questions to this ADR:

1. In a community channel, which participant may author a `Commit` that changes
   group membership?
2. After a member is blocked or banned, who triggers the `Remove Commit` that
   rotates the group secrets and excludes the removed device from the next
   epoch?

ADR 0007 also defers to this ADR the enforcement surface: block/ban policy must
cover every entry point, not only application messages, and the workflow must
say what happens when no authorized client is online to produce the Remove
Commit.

Facts that constrain the answer:

- Community channels are groups whose membership derives from Social data
  (`member.joined`, `member.left`, `member.banned` soft references; architecture
  §6). Chat has no independent authority over community membership — the
  Social API owns it.
- Authorization is enforced server-side. The client is never the authority for
  ownership, permissions, membership, or moderation status.
- MLS Commits are authored by clients. The chat service validates and orders
  Commits; it does not hold group private keys and cannot author one on a
  member's behalf. The server authorizes *who may submit* a Commit; it never
  validates the Commit's cryptography, which clients do.
- The server increments `crypto_state_version` and distributes membership
  changes (architecture §3.5), but key rotation itself is a client operation.
- Chat is also the Authentication Service (ADR 0007): it binds signature keys
  to users and serves KeyPackages, so a blocked or banned user who can still
  claim a KeyPackage or register a device could open a fresh session.
- A removed or banned member may retain copies of messages already decrypted.
  Rotation protects future messages only (architecture §3.5, §6).
- Per-aggregate ordering only: a Commit's canonical-epoch rule is scoped to a
  single conversation.

## Decision

### 1. Commit authorship in community channels

A `Commit` that changes membership for a community channel may be authored by a
client that, at the time of submission, satisfies **both** conditions:

- it is an active member of the conversation according to chat-side membership
  state, **and**
- its role permits member administration for that conversation (community
  owner or moderator, per the role mirrored from Social).

For non-administrative Commits (adding the author's own new device, advancing an
epoch the author is already a member of), any active member may author the
Commit.

The chat service re-checks both conditions server-side on every Commit
submission and rejects (HTTP `403`) any Commit whose author lacks the required
role at submission time. This check is authoritative; a client that believes it
is authorized gains nothing by bypassing its own UI.

### 2. Who triggers the Remove Commit after block or ban

Removal is **two separate acts**, split by who is able to perform each:

- **Moderation action (Social side):** banning a member, or blocking a user, is
  performed through the Social API / moderation path, exactly as today. Chat
  does not decide who is banned.
- **Key rotation (chat side):** after chat ingests `member.banned` (or the
  block propagates to a 1:1 conversation), the **conversation's remaining
  authorized administrators** author the `Remove` proposal and the resulting
  `Commit`. The chat service distributes the membership change and increments
  `crypto_state_version`; the removed device is excluded from the next epoch.

**Device-list fetch:** the removing client resolves the devices to exclude from
chat-side state — the conversation's member device list plus the banned
identity's device list as chat already stores it (`chat_devices`). Chat is the
Authentication Service and already owns device registration, so no new
cross-service lookup is introduced. The client submits a `Remove` for each
device it wants excluded in the same Commit.

**If no authorized client performs the Commit** (no administrator online, or a
client bug):

1. The chat service still stops routing sends from the removed identity
   immediately. Routing control is the real-time enforcement; the Remove Commit
   is defense in depth (ADR 0007).
2. Chat marks the conversation's crypto state as *pending removal* and raises a
   visible flag to the remaining administrators (and, for a 1:1 conversation, to
   the other participant) so the rotation is retried on next client activity.
3. Sends from remaining members are **not** blocked: refusing to send would let
   a single banned member deny service to the whole conversation. The group
   simply stays on the old epoch until a Commit lands, and clients surface the
   stale-membership state.
4. If the conversation ends up with no authorized author at all, the fallback
   order is: any remaining member may author the Remove Commit, and only if no
   member remains is the conversation closed to new sends.

Which fallback applies is fixed by the rules above, not decided ad hoc at
removal time.

### 3. Enforcement surface for block/ban

The block/ban decision applies to **every** chat entry point that could mint or
refresh a session, not only to application messages (ADR 0007). Concretely, a
blocked or banned identity is rejected by the chat service for:

- **KeyPackage claim/upload:** no KeyPackage may be fetched for, or registered
  by, a blocked or banned identity.
- **Conversation join:** no join or re-join of a community channel or 1:1
  conversation the identity is barred from.
- **Device registration:** no new device may bind a signature key to a blocked
  or banned account.
- **Send and Commit submission:** no application message, Proposal, Commit, or
  Welcome is accepted from the identity.

Each check reads the same chat-side block/ban/membership state, so one
consistency boundary governs all four. This is server-side only; a client that
skips its own check gains nothing.

### 4. What the server guarantees

- The chat service never authors a Commit and never holds group private keys.
- The server orders Commits per conversation and applies the first-accepted
  Commit for an epoch as canonical (ADR 0007).
- The server rate-limits and authorizes Commit submission by role and membership
  (§1); it does not validate Commit cryptography, which clients do.
- The server distributes `member.banned` / block-driven membership changes and
  increments `crypto_state_version`, but does not — and cannot — verify that a
  client actually performed the rotation. Clients validate every Commit and
  reject stale epochs.
- Rotation does not revoke already-decrypted history. Banned members may keep
  old plaintext copies.

## Consequences

- Commit authorization is a server-side check tied to conversation roles, so it
  is enforceable and testable, but it depends on chat-side membership state
  being fresh; consumer lag on `member.banned` directly delays the ability to
  exclude a banned device (architecture §6 requires alerting on this lag).
- The Remove Commit depends on an administrator being present. Conversations
  that lose all administrators need the documented fallback, which is a real
  edge case for small groups.
- Splitting the moderation act (Social) from the rotation act (chat) preserves
  the ownership boundary: chat never decides moderation outcomes, Social never
  touches group keys.
- Because the server cannot author Commits, a client-side bug that fails to
  rotate leaves the group on stale keys until a working client commits. This is
  an accepted residual risk of MLS with a non-holding Delivery Service. Sends
  from remaining members stay open during that window, so availability wins
  over immediate cryptographic exclusion; routing control covers the banned
  identity in the meantime.
- The four enforcement points (KeyPackage, join, device registration, send) all
  read one chat-side state, so a stale `member.banned` projection weakens all
  four at once. Consumer-lag alerting is therefore security-relevant, not just
  operational (architecture §6).
- Excludes and epochs remain protocol-specific, so this decision must be
  reflected in the chat contracts and in `chat_db` schema work before
  protocol-specific migrations land.

## Alternatives considered

- **Server-authored Remove Commit.** The chat service authors the Commit on
  ban. Rejected: the server would need the group's private signing key, which
  violates the rule that private identity and session keys never reach the
  server, and it breaks the model that clients author Commits.
- **Any member may author any Commit.** Simplest, but lets a non-admin member
  change group membership, which contradicts server-side authorization for
  permissions and membership.
- **Moderator performs the ban and the rotation as one action.** Rejected: it
  couples Social moderation to chat key material across a service boundary and
  makes the Social API responsible for an E2EE operation it does not own.
- **Server auto-rotates keys by rewriting membership without a Commit.**
  Rejected: impossible without group keys, and it would silently break the
  epoch/Commit ordering that ADR 0007 relies on.
- **Enforce block/ban only at message send.** Rejected: a banned user could
  still claim a KeyPackage or register a new device and open a fresh MLS
  session, defeating the ban (ADR 0007).
- **Close the conversation to all sends until the Remove Commit lands.**
  Rejected: it lets a single banned member deny service to every remaining
  member. Availability is preferred; routing control already stops the banned
  identity.
