# ASN Glossary

Domain vocabulary used across ASN services, contracts, documentation, and code.
Definitions describe what a term means **in this project**; where a term also has
a general industry meaning, the ASN-specific rule is stated explicitly.

Use this file when writing code, contracts, ADRs, tests, or documentation. If a
term is missing, do not invent one silently: add it here in the same change and
link the architecture section that defines it.

- Product name: **ASN** (Arabian Social Network). No alternate product name is
  used in code, docs, UI, or file names.
- Tags: `[Social]`, `[Chat]`, `[Moderation]`, `[Broker]`, `[Client]`,
  `[Contract]`, `[Data]`.

## Terms

**Account deletion** `[Social]` — The 30-day grace workflow started when a user
requests deletion. The request can be cancelled during the grace period. At the
end, a purge workflow runs unless an active case places a deletion hold. See
architecture §4.15.

**ADR (Architecture Decision Record)** `[Platform]` — A numbered, dated record
of a significant decision in `docs/decisions/`, with context, decision,
consequences, and alternatives. An accepted ADR overrides prose in other
documents. See `docs/decisions/README.md`.

**Aggregate** `[Broker]` — A consistency unit identified by `aggregate_type` and
`aggregate_id` (for example one conversation). Events carry an
`aggregate_version`; ordering is guaranteed only per aggregate, never globally.

**Aggregate version** `[Broker]` — A monotonic version of one aggregate, used by
consumers to reject stale updates. It is not an API version, an event schema
version, or a message sequence.

**Appeal** `[Moderation]` — A request to review a moderation action, with status
`open`, `upheld`, or `overturned`. The reviewer must differ from the moderator
who made the original decision.

**Article** `[Social]` — A long-form post with `kind = 'article'` and one
`post_articles` row. Source Markdown is canonical; sanitized HTML is a derived
cache that is regenerated when the sanitizer or parser version changes.

**ASN** `[Platform]` — Arabian Social Network, the project and product name.

**At-least-once delivery** `[Broker]` — The delivery guarantee: every accepted
event is delivered one or more times. Duplicates are expected, so consumers must
be idempotent. ASN never promises exactly-once delivery.

**Attachment** `[Chat]` — Metadata linked to a logical message, pointing at an
encrypted object in R2. The upload must be `ready`, owned by the sender, and
scoped to the conversation. Decryption keys, real MIME type, file name, and
dimensions travel inside the encrypted message payload.

**Audit log** `[Moderation]` — The append-only staff action record. The
application role may `INSERT` only; `UPDATE` and `DELETE` are denied. Viewing
sensitive E2EE evidence is itself an audited action.

**Authentication** `[Platform]` — Proving who the caller is (user session, staff
session, or service credential). Distinct from authorization.

**Authorization** `[Platform]` — Deciding what an authenticated caller may do.
Every service enforces it for its own resources; the client is never the
authority for ownership, permissions, membership, or moderation status.

**Backup** `[Client]` — A client-side chat snapshot. The mobile app creates a
consistent SQLite snapshot with `VACUUM INTO`, encrypts it locally, and uploads
only the encrypted file to Google Drive. The server never receives plaintext
backup content or recovery secrets. See architecture §3.19.

**Block** `[Social]` — A platform-wide one-way block owned by Social in
`user_blocks`, keyed by `(blocker_id, blocked_id)`. It emits `user.blocked` /
`user.unblocked`. Chat consumes it into `chat_block_edges`; a block never changes
friendship status to `blocked`. Chat fails closed when its block projection is
known to be stale beyond the defined threshold.

**Broker (event broker)** `[Broker]` — The custom Elixir/OTP service that stores
and delivers domain events, persisted in `broker_db`. It owns the event log,
subscriptions, deliveries, retries, and dead letters, but never owns social,
chat, or moderation business entities.

**Broker delivery** `[Broker]` — One attempt to hand an event to one
subscription. A delivery is leased (visibility timeout), acknowledged or
negative-acknowledged, and retried with bounded backoff before becoming a dead
letter. Lease and acknowledgement state live in `broker_db`.

**Broker subscription** `[Broker]` — A durable consumer registration that selects
which events a service receives. It has a status (`active`, `paused`) and can be
replayed from a stored event ID or timestamp. Not to be confused with a billing
subscription.

**Case** `[Moderation]` — The unit of moderation work opened for a target.
Statuses are `open`, `in_review`, `actioned`, and `closed`; one active case per
`(target_type, target_id)` is enforced by a partial unique index. Many reports
may point to one case.

**Channel** `[Social]` — A community channel
(`community_channels.kind = 'feed' | 'chat'`). A `chat` channel maps through
`channel_id` to exactly one Chat-owned conversation. Not to be confused with a
Phoenix Channel, which is a WebSocket transport concept.

**Ciphertext** `[Chat]` — Encrypted bytes. For chat it is stored as `bytea` in
`message_payloads`; the server never stores the corresponding plaintext.

**Citext** `[Data]` — A PostgreSQL case-insensitive text type used for usernames,
community slugs, and normalized hashtags.

**Claim check** `[Broker]` — A pattern where a large payload is stored outside the
event (for example in object storage) and the event carries only a reference.
Broker events carry identifiers and small deltas, not blobs.

**Comment** `[Social]` — A server-readable plaintext reply to a post, with
`parent_id` and `root_id` for reply chains. Replies cannot cross posts. Status is
`visible`, `hidden`, or `removed`. Unlike chat content, comments are not E2EE.

**Community** `[Social]` — A social group with privacy (`public`, `restricted`,
`private`), members, roles, channels, rules, invites, and its own audit log.
Community chat channels are still E2EE.

**Community report** `[Social]` — A report handled by community moderators inside
Social. If escalated, it creates a linked platform case in Moderation; the
escalation keeps a soft reference and history instead of duplicating the report.

**Community role** `[Social]` — A named permission set in `community_roles`,
assigned through `member_roles`. A community has at most one default role
(partial unique index); removing or changing roles is audited.

**Consumer lag** `[Broker]` — How far a subscription is behind the event log
(by event ID or timestamp). Security-sensitive projections alert on lag; they
must not silently continue with stale data.

**Contract** `[Contract]` — A machine-readable interface definition:
OpenAPI 3.x under `contracts/openapi/` or versioned JSON Schema under
`contracts/events/`. Contracts are the source for generated clients and types
and are validated in CI.

**Conversation** `[Chat]` — A direct chat or a community chat thread, owned by
Chat. Every conversation has a `kind` (`direct` or `community`), a per-
conversation `last_seq`, and crypto protocol/version fields. A direct
conversation has a deterministic `direct_key`; a community conversation maps to
one `channel_id`.

**Conversation member** `[Chat]` — A user's membership in a conversation:
`role` (`member` or `admin`), `last_read_seq`, `muted_until`, `joined_at`,
`left_at`, and `membership_version`. `last_read_seq` is a cursor, not an exact
unread count.

**Counter** `[Data]` — A denormalized count (likes, comments, reposts, actors).
Counters are maintained asynchronously and must be rebuildable from source data;
they are never the only source of truth.

**Cross-database soft reference** `[Data]` — A reference to another service's
data stored as a plain ID, documented as `ref: <db>.<table>.<column>`. There is
no cross-database foreign key and no cross-database transaction.

**Cursor (keyset pagination)** `[Contract]` — A stable, opaque position in an
ordered collection, used instead of offset pagination for timelines, message
history, and other large or fast-changing lists. Message sync uses an explicit
cursor such as `(updated_at, id)`. `last_message_at` is inbox ordering only and
is **not** a sync cursor.

**Dead letter** `[Broker]` — The state of an event delivery after retries are
exhausted. Dead letters are inspectable and replayable; they are not silently
discarded.

**Deletion hold** `[Social]` — A block on account purge while an unresolved active
report/case requires review. Dismissed or historical reports must not block
deletion indefinitely.

**Delivery receipt** `[Chat]` — An acknowledgement that one of a user's devices
received a message (`message_receipts.delivered_at`). It is not proof that the
user saw a notification or read the message.

**Device (chat device)** `[Chat]` — One installed client with a cryptographic
identity. The server stores the public identity key, its fingerprint, platform,
and status (`active`, `revoked`, `pending_verification`). Private identity keys
and session state stay on the device.

**Direct conversation** `[Chat]` — A one-to-one chat with a deterministic
`direct_key` derived from the sorted pair of user IDs. It has no
`community_id` or `channel_id`.

**E2EE (end-to-end encryption)** `[Chat]` — Encryption where only the
communicating clients can decrypt content. ASN applies it to direct and community
chat, including message content, attachments, and reactions. The server stores
opaque envelopes and cannot inspect plaintext or scan encrypted attachments for
malware.

**Envelope** `[Chat]` — The opaque ciphertext payload for a message revision,
stored in `message_payloads`. An envelope is either `shared` (one ciphertext for
authorized members, `recipient_device_id IS NULL`) or `per_device` (one ciphertext
per recipient device). A revision never mixes both shapes.

**Event** `[Broker]` — A versioned fact published by a producing service, such as
`user.created` or `friendship.accepted`. Events are asynchronous integration, not
a replacement for a synchronous REST response. The business catalog is in
architecture §7.

**Event envelope** `[Broker]` — The common event wrapper: `event_id`, `type`,
`schema_version`, `occurred_at`, `aggregate_type`, `aggregate_id`,
`aggregate_version`, `trace_id`, and `payload`.

**Event ID** `[Broker]` — A stable UUID identifying one event across outbox
retries and broker redelivery. Consumers deduplicate on it.

**Evidence (E2EE report evidence)** `[Moderation]` — The bounded content a
reporter explicitly submits from a client, with provenance and a content hash,
stored in `content_snapshots`. It is not a server-side snapshot of live chat and
must never be expanded with unrelated history.

**Exactly-once delivery** `[Broker]` — Not provided and not assumed anywhere in
ASN. Design for at-least-once plus idempotent consumers.

**Fail closed** `[Platform]` — Deny or block an action when required state is
stale or unknown, rather than allowing it. Used for security-sensitive
projections such as blocks and bans.

**Feature flag** `[Social]` — A configuration switch with a defined scope
(global, plan, user, or environment) and deterministic precedence. Feature-flag
values never contain secrets.

**Feed** `[Social]` — The ranked home timeline. Candidates come from friends
(`friend_edges` projection of Chat friendships), followed accounts (`follows`),
and followed hashtags (`hashtag_follows`). Candidate source priority is not the
final rank; recency and relationship/source relevance are combined by the
ranker.

**Follow** `[Social]` — A one-way relation in `follows`, keyed by
`(follower_id, followee_id)`. It is not a friendship and does not grant chat
permission.

**Friendship** `[Chat]` — A Chat-owned, unordered, mutual relation stored one row
per pair (`user_a_id < user_b_id`), with status `pending`, `accepted`, or
`declined`. It is distinct from follows and from blocks.

**Group key rotation** `[Chat]` — The client-side cryptographic operation that
changes the group sending state after a membership/device/key change, so that
removed members cannot decrypt future messages. The server increments
`crypto_state_version` and distributes the change. Rotation cannot revoke
knowledge of messages already decrypted. The exact protocol policy is open.

**Hashtag follow** `[Social]` — A user's subscription to a hashtag, used as a feed
candidate source. Private community content never appears in public hashtag
pages or trends.

**Idempotency key** `[Contract]` — A client-supplied value that makes a retried
create/command safe to execute once. Chat messages use `client_message_id`;
reactions use `client_event_id`; payment events use the provider event ID.

**Idempotent consumer** `[Broker]` — A consumer that produces the same result
when it processes the same event more than once. It deduplicates on `event_id`
and rejects stale content using `aggregate_version`.

**Inbox** `[Chat]` — A user's conversation list, ordered by
`conversations.last_message_at`. Inbox ordering is not a durable sync cursor.

**Keychain / Keystore** `[Client]` — OS secure storage for mobile secrets (the
SQLite encryption key, backup key material, device private keys). Keys are never
stored in AsyncStorage, JS bundles, or logs.

**Lease / visibility timeout** `[Broker]` — The period during which a delivered
event is reserved for one consumer and hidden from others. If the consumer does
not acknowledge before the lease expires, the delivery becomes eligible again.
Long handlers renew the lease.

**Local plaintext** `[Client]` — Decrypted content stored on the mobile device.
It exists only inside the encrypted SQLite database. The server-side store is
ciphertext only.

**Media upload** `[Chat]` — The tracked lifecycle of an encrypted object:
`pending`, `processing`, `ready`, `rejected`, or `expired`. Uploads normally
expire about 15 minutes after creation; a `ready` but unattached object may be
deleted after 24 hours. Server-side plaintext scanning is not possible.

**Message** `[Chat]` — The logical message row. It has no `body` column: content
lives in encrypted payloads. Routing metadata includes `payload_kind`,
`payload_mode`, `client_message_id`, `sender_device_id`, and `seq`.

**Message payload** `[Chat]` — See **Envelope**. Identified by `message_id`,
`revision_no`, and optional `recipient_device_id`, with `protocol_version` and
`ciphertext`.

**Metadata minimization** `[Chat]` — The practice of limiting what the server can
see. E2EE does not hide routing metadata, timestamps, sequence numbers, member
IDs, attachment sizes, receipts, or group membership; the approved list is an
open decision.

**MLS (Messaging Layer Security)** `[Chat]` — IETF RFC 9420, an asynchronous group
key establishment protocol with forward secrecy and post-compromise security for
groups from two to thousands. A candidate E2EE protocol; not yet selected.

**Moderation action** `[Moderation]` — A decision requested by Moderation and
applied by the owning service. Types include `remove_content`, `warn`, `mute`,
`suspend`, `ban`, `restore`, and `dismiss`. Delivery status is `pending`,
`applied`, or `failed`.

**Moderator** `[Moderation]` — A staff member with role `admin`, `senior`, or
`moderator`, authenticated through a separate Auth0 tenant/connection with
mandatory MFA. Moderators cannot read ordinary E2EE plaintext.

**Mute** `[Chat]` — A per-conversation member setting
(`conversation_members.muted_until`) that suppresses notifications; it does not
block messages or change membership.

**Notification** `[Social]` — A grouped in-app notification row with
`group_key`, `actor_count`, `target_type`, and `target_id`. Unread grouping uses
a partial unique index. Remote push payloads remain generic.

**Object key** `[Data]` — The storage key for an object in R2, stored instead of
a permanent URL. Layout is
`{scope}/{owner_id}/{yyyy}/{mm}/{upload_id}.{ext}`, where `pub` is public media
and `prv` is private/encrypted chat media.

**OpenAPI** `[Contract]` — The OpenAPI 3.x specification used for every REST
service contract. Clients and types are generated from it; generated code is
never hand-edited.

**Outbox (transactional outbox)** `[Broker]` — The `outbox_events` table written
in the same database transaction as the business change. A separate relay
publishes committed rows to the broker; this avoids a dual-write between the
database and the broker. The relay marks a row published only after broker
acknowledgement.

**Ownership boundary** `[Data]` — The rule that exactly one service owns writes
to a database/domain. Other services keep read-only projections and integrate
through contracts and events.

**Partial unique index** `[Data]` — A PostgreSQL index that enforces uniqueness
only for rows matching a condition. ASN uses it for conditional uniqueness such
as one active case per target, one default role per community, one shared
envelope per message revision, and one unread notification per grouping key.

**Payload kind** `[Chat]` — Coarse routing metadata for a message: `text`,
`media`, `voice`, `system`, or `control`. It is server-visible and should not be
used to infer content. System and control messages do not count as user activity.

**Payload mode** `[Chat]` — How an envelope is addressed: `shared` (one ciphertext
for authorized members) or `per_device` (distinct ciphertext per recipient
device).

**Per-aggregate ordering** `[Broker]` — ASN guarantees ordering only within one
`aggregate_id` per subscription, with at most one in-flight delivery per
aggregate. Independent aggregates and conversations proceed concurrently.

**Per-device envelope** `[Chat]` — An encrypted payload addressed to one recipient
device (`recipient_device_id` is set). Used when the protocol cannot or should
not share one ciphertext.

**Plan** `[Social]` — A configured set of limits and entitlements. Every account
is treated as Free while `subscriptions_enabled = false`, regardless of
partially populated subscription rows. Limits are enforced server-side.

**Post** `[Social]` — Social content owned by Social, with kinds `original`,
`quote`, and `article`. Unlike chat messages, post bodies are server-readable
plaintext. Posts have visibility/status and denormalized counters.

**Prekey** `[Chat]` — Public key material published by a device so others can
start an asynchronous encrypted session. Kinds include `signed` and `one_time`.
Only public material is stored; one-time key claiming must be atomic.

**Presence** `[Chat]` — Online/last-seen state. It is returned only when privacy
allows it (`show_presence` and Social's `show_online_status`); it is not a
message or a receipt.

**Problem Details (RFC 9457)** `[Contract]` — The standard JSON error shape used
as the preferred basis for ASN API errors, with a stable machine-readable code
and a request/correlation ID. See RFC 9457.

**Projection** `[Data]` — A read-only local copy of data owned by another service,
for example `chat_users`, `chat_block_edges`, or `friend_edges`. A projection is
never authoritative and is updated idempotently from events.

**Purge** `[Social]` — The final, per-service deletion of account data after the
grace period, carried out through a deletion map and idempotent events. E2EE
ciphertext deletion cannot erase plaintext already seen or copied by a recipient.

**Push device** `[Chat]` — A registered FCM, APNs, or web push destination. The
token is secret-like and restricted in logs. Notifications are generic ("New
message") with no previews, names, or content.

**R2** `[Data]` — Cloudflare R2 or another S3-compatible object store. Services
store object keys, not public URLs, and build authorized URLs at read time.

**Reaction (chat reaction)** `[Chat]` — An encrypted response attached to a
message (`message_reactions`), stored as ciphertext with a `client_event_id`.
Social post likes are separate and server-readable.

**Read receipt** `[Chat]` — An account-level acknowledgement that a user's
device reported reading a message (`message_receipts.read_at`). Large community
channels use `last_read_seq` instead of per-message receipts.

**Reconciliation** `[Broker]` — The process that compares authoritative state with
projections using owner-published events/snapshots or administrative APIs. It
never reads another service's database directly.

**Recovery key** `[Client]` — The secret used to decrypt a backup after restoring
on a new device. The method (recovery key, passphrase, passkey-supported wrapping,
or a reviewed combination) is an open decision.

**Replay** `[Broker]` — Re-delivering stored events to a subscription from an
earlier position. Consumers must remain idempotent because replay re-delivers
old events.

**Report** `[Moderation]` — A user or automod submission about a target (`post`,
`comment`, `user`, `message`, `community`). Statuses are `open`, `triaged`,
`resolved`, and `dismissed`. For an E2EE message, evidence must come from the
reporting client.

**Report reason** `[Moderation]` — A configured reason code (`spam`,
`harassment`, `nsfw`, `violence`, `csam`, `self_harm`, and reviewed additions)
with severity `low`, `medium`, `high`, or `critical` and an `auto_escalate` flag.

**REST** `[Contract]` — The only application HTTP API style in ASN. No GraphQL or
gRPC. The broker is for asynchronous events and never replaces a synchronous
response.

**Revision (message revision)** `[Chat]` — A version of a message payload,
identified by `revision_no`. Edits create a new encrypted revision; clients fetch
the latest revision and replace displayed content only after successful local
decryption.

**Schema version** `[Broker]` — The version of an event payload schema
(`schema_version`), separate from `aggregate_version` and from the REST API
version.

**Sequence (`seq`)** `[Chat]` — A conversation-local monotonic message number,
allocated by locking and updating the conversation row
(`last_seq = last_seq + 1`). Unique per conversation; never global. Different
conversations proceed concurrently.

**Shared envelope** `[Chat]` — One ciphertext deliverable to all authorized
members of a conversation (`recipient_device_id IS NULL`).

**Signal / Sesame** `[Chat]` — Signal's protocol family and its Sesame algorithm
for managing asynchronous sessions across multiple devices. A candidate E2EE
approach; not yet selected. No custom cryptography may be invented.

**Soft delete** `[Data]` — Marking content with `deleted_at` or a status such as
`hidden`/`removed` instead of physically removing it immediately. Physical purge
is governed by retention and account-deletion rules.

**Soft reference** `[Data]` — See **Cross-database soft reference**.

**Source of truth** `[Data]` — The owning service's database. The broker, event
log, projections, caches, and clients are never sources of truth.

**SQLCipher** `[Client]` — A SQLite fork that adds 256-bit AES encryption of the
database file. A candidate for mobile encryption-at-rest; support in the chosen
React Native SQLite library must be verified.

**Streak** `[Chat]` — A per-friendship counter of committed, user-originated
messages in a direct conversation between accepted, unblocked friends. System
and control messages do not count; the server derives `is_user_activity`. Day
boundary is `Africa/Cairo`. Resetting a friendship resets the current count but
keeps the best count.

**Strike** `[Moderation]` — A recorded violation attached to a user
(`user_strikes`), used for escalation and policy thresholds. Retention and
anonymization after account purge are defined by policy.

**Subscription** `[Social]` — A billing/plan record. Not to be confused with a
broker subscription. Payment events are idempotent on the provider event ID. Every
account is Free while `subscriptions_enabled = false`.

**Tenant (Auth0 tenant)** `[Moderation]` — The separate identity tenant used for
staff authentication. Staff sessions are never shared with public users.

**Timestamptz** `[Data]` — PostgreSQL `timestamp with time zone`, stored in UTC.
The platform streak/activity day boundary is the `Africa/Cairo` date, which is a
product rule rather than a database timezone.

**Transactional outbox** `[Broker]` — See **Outbox**. The pattern guarantees that
the business state and the event intent commit atomically; a relay publishes
after commit. Duplicate publication is possible, so consumers are idempotent.

**Typing indicator** `[Chat]` — An ephemeral live signal on the WebSocket path.
It is not a message, is not stored durably, and is not included in sequence or
receipts.

**Unread count** `[Chat]` — The number of unread messages as defined by the
product policy. `last_seq - last_read_seq` is only a rough sequence gap: it
includes the user's own messages and system/control events, so it must not be
reported as an exact unread count.

**Upload** `[Chat]` — See **Media upload**.

**UUIDv7** `[Data]` — A time-ordered UUID defined by RFC 9562: 48 bits of Unix
milliseconds followed by random bits. Generated in application code with one
vetted library per runtime. PostgreSQL 18 provides `uuidv7()` as well, but the
project does not use database-generated IDs by default.

**VACUUM INTO** `[Client]` — A SQLite statement (3.27.0+) that writes a vacuumed,
consistent snapshot to a new file; it is an alternative to the backup API. Used
for mobile backups instead of copying a live database. The target file must not
already exist.

**WAL (write-ahead log)** `[Client]` — SQLite's log mode that keeps recent changes
in `-wal` (and `-shm`) files. This is exactly why a backup must use a snapshot
mechanism such as `VACUUM INTO`, never a copy of the main file alone.

**Web E2EE parity** `[Client]` — Whether the React web client ships E2EE at the
same time as mobile. The timing is an open decision; there is no silent plaintext
fallback in an E2EE conversation.

**WebSocket / Phoenix Channel** `[Chat]` — The live-delivery path for connected
clients (new messages, presence, typing). It is not durable history: after
reconnects, clients recover missed messages through REST and a stable cursor.

## Naming rules

- Call a community a **community**, never a "group". "Group" is reserved for
  cryptographic group state, not a product object.
- Call a conversation a **conversation**, never a "thread" or "room". The current
  design has no chat thread model.
- Call a one-to-one chat a **direct conversation**, not a "DM" in contracts or
  schema.
- A **channel** is a community channel; a Phoenix Channel is a transport detail.
  Say "WebSocket channel" when referring to the transport.
- A **service** is a deployable backend. Avoid "server" when the ownership
  boundary matters.
- A **tenant** means the Auth0 staff tenant unless another tenant is named.
- A **post** is social plaintext content; a **message** is E2EE chat content.
  Never use them interchangeably.

## Frequently confused pairs

| Pair | Distinction |
|---|---|
| Follow vs friendship | Follow is one-way Social graph data. Friendship is a mutual, Chat-owned relation with request/accept/decline states. |
| Friendship vs block | Friendship is mutual and Chat-owned. A block is one-way, Social-owned, and never rewrites friendship status. |
| Report vs case | A report is a submission. A case is the work item; multiple reports can feed one active case per target. |
| Community report vs platform report | Community reports are handled in Social by community moderators; escalation creates a linked platform case in Moderation. |
| Channel vs conversation | A community channel is Social-owned metadata. A `chat` channel maps to exactly one Chat-owned conversation. |
| Conversation vs inbox | A conversation holds messages and sequence. The inbox is the user's ordered conversation list. |
| Message vs envelope | A message is the logical row. An envelope is one encrypted payload revision for that message. |
| Attachment vs upload | An upload is the object lifecycle. An attachment is the message link to a `ready`, owned upload. |
| Delivery receipt vs read receipt | Delivery means a device received it; read means a device reported reading it. Neither proves the user saw a notification. |
| Broker subscription vs billing subscription | Broker subscription is an event consumer registration. Billing subscription is a plan/payment record. |
| Broker delivery vs message delivery | Broker delivery is an event handoff with a lease. Message delivery is a chat receipt. |
| Source of truth vs projection | Only the owning service's database is authoritative. Projections are read-only copies updated from events. |
| Server ciphertext vs local plaintext | The server stores envelopes only. Mobile keeps plaintext inside its encrypted SQLite database. |
| Post body vs chat message | Post content is server-readable plaintext. Chat message content is E2EE and never present in plaintext on the server. |
| Auth0 tenant vs database | The staff tenant is an identity boundary. It does not own business data or replace service authorization. |

## Version and sequence fields

These fields are easy to mix up; they measure different things.

| Field | Scope | Meaning |
|---|---|---|
| `aggregate_version` | One aggregate | Monotonic business version used to reject stale events. |
| `source_version` | One projection row | Latest source aggregate version applied to that projection. |
| `schema_version` | One event type | Version of the event payload schema. |
| `crypto_protocol_version` | One conversation | Envelope/protocol version clients must understand. |
| `crypto_state_version` | One conversation | Incremented on membership/device/key-state changes that require client key rotation. |
| `membership_version` | One conversation member | Versions a membership change and assists key-state invalidation. |
| `revision_no` | One message | Increments on edits; identifies the payload revision. |
| `seq` | One conversation | Monotonic message position allocated per conversation. |
| `last_seq` | One conversation | Highest sequence issued in that conversation. |
| `last_read_seq` | One member | Cursor for the last contiguous sequence the member acknowledged as read. |
| `event_id` | One event | Stable identity across retries and redelivery. |
| `client_message_id` | One sender | Client idempotency key for message creation. |
| `client_event_id` | One actor | Client idempotency key for reactions. |

## Terms intentionally left undefined

Do not assume a concrete value for these; they are open decisions in
architecture §9 and must be resolved by an ADR before code depends on them.

- The real E2EE protocol and its libraries (Signal/Sesame vs MLS/RFC 9420).
- Web E2EE parity timing.
- Broker transport, lease/retry defaults, retention windows, payload limits, and
  replay authorization.
- TypeScript HTTP framework, query layer, validation, and migration tooling.
- React Native SQLite library and its SQLCipher support.
- Backup recovery method (recovery key, passphrase, passkey wrapping).
- Group key rotation details and pre-join history delivery.
- The approved server-visible metadata list.
- Report evidence retention and deletion holds.
- UUIDv7 library choice per runtime.

## Standards referenced

Definitions in this glossary were checked against the official sources below.

- UUIDv7: RFC 9562, *Universally Unique IDentifiers (UUIDs)* (obsoletes
  RFC 4122) - https://www.rfc-editor.org/rfc/rfc9562.html
- MLS: RFC 9420, *The Messaging Layer Security (MLS) Protocol* -
  https://www.rfc-editor.org/rfc/rfc9420.html
- Problem Details: RFC 9457, *Problem Details for HTTP APIs* (obsoletes
  RFC 7807) - https://www.rfc-editor.org/rfc/rfc9457.html
- Signal/Sesame: *The Sesame Algorithm: Session Management for Asynchronous
  Message Encryption* - https://signal.org/docs/specifications/sesame/
- Signal Double Ratchet - https://signal.org/docs/specifications/doubleratchet/
- Transactional outbox pattern -
  https://microservices.io/patterns/data/transactional-outbox.html
- SQLite `VACUUM INTO` (added in 3.27.0) -
  https://www.sqlite.org/lang_vacuum.html
- SQLCipher - https://github.com/sqlcipher/sqlcipher
- Google Drive `drive.file` scope -
  https://developers.google.com/workspace/drive/api/guides/api-specific-auth
- OpenAPI Specification - https://spec.openapis.org/oas/latest.html

## Maintenance

- Update this file in the same change whenever a term, field, enum value, or
  ownership rule changes.
- Do not add speculative terms or define an open decision by accident.
- If a definition conflicts with the architecture document or an accepted ADR,
  the ADR wins; report and correct the conflict rather than keeping both.
