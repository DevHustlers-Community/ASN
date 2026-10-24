# Real-time Chat Feature (`src/features/chat`)

**Status:** planned — no implementation yet.

Client implementation for direct and group messaging.

> **Note on E2EE & Web Key Storage:** Web E2EE parity and web cryptographic key storage are currently open architectural decisions (pending ADR 0010 and architecture §9). Plaintext messages never reach the server; development relies strictly on opaque binary envelopes (`dev-opaque-v1`).

## UI Physics & Message Delivery

- **Consecutive Message Grouping (4px Gap):**
  - Consecutive messages from the same sender within 60s share a `4px` vertical gap (`space-y-1`).
  - Avatar appears only on the terminal message in the sequence.
  - Adjacent bubble corners flatten (`rounded-br-sm` / `rounded-bl-sm`).
- **Read Receipts:**
  - In direct chats: per-message status (`✓` sent, `✓✓` delivered, `✓✓` read).
  - In channels/group conversations: per-conversation `last_read_seq` cursor tracking per `architecture-and-schema.md` §3.11.
- **Streaks:**
  - Streaks (`chat_db.streaks`) are friendship-based direct messaging streaks, not community-wide streaks.
- **Presence & Live Indicators:**
  - Online/offline status and typing indicators delivered through Phoenix Channels WebSockets.
