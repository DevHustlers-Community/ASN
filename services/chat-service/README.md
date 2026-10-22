# Chat service

Elixir + Phoenix + Ecto service that owns `chat_db`.

**Owns:** friendships, chat privacy settings, direct and community
conversations, conversation membership, opaque message envelopes, public device
identity/prekey material, media upload tracking, receipts, push devices, and chat
streaks.

**Does not own:** accounts/profiles (projected from Social), platform blocks
(projected from Social), moderation cases, or the event log.

**Planned layout (`lib/asn_chat/`):**

| Context | Purpose |
|---|---|
| `accounts/` | `chat_users` projections |
| `conversations/` | Direct/community conversations, membership, privacy |
| `messages/` | Sequence issuance, envelopes, edits, tombstones |
| `attachments/` | Encrypted upload lifecycle |
| `read_receipts/` | Read cursors and receipts |
| `devices/` | Device registry and public prekeys |
| `crypto/` | Protocol state, key rotation triggers, envelope validation helpers |
| `blocks/` | `chat_block_edges` projection and fail-closed checks |
| `delivery/` | Channel fan-out, push, presence |
| `events/` | Outbox writer, publishers, consumers |

**Hard rules:**

- No plaintext message body exists in any column, DTO, log, event, trace, or push
  payload. Envelope bytes only; `dev-opaque-v1` is still an envelope.
- Sequence issuance locks one conversation row; never a global chat writer.
- `conversations.last_seq` and `messages.seq` are authoritative for ordering;
  `last_message_at` is inbox ordering only, never a sync cursor.
- Device-specific envelopes must belong to active, authorized devices.
- Private keys never reach the server; only public protocol material is stored.

**Real-time:** Phoenix Channels for live delivery and presence. REST/sync remains
the recovery path after reconnects; clients deduplicate on message ID.

**Tests:** `test/unit`, `test/integration` (real PostgreSQL), `test/failure`
(prekey races, duplicate send, reconnect sync, membership removal).

**Status:** not scaffolded. The only persisted protocol values today are
`dev-opaque-v1` placeholders.
