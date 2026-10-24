# Real-time Chat Feature (`src/features/chat`)

Client implementation for encrypted direct and community messaging.

## Non-Negotiable E2EE Rules

1. **No Plaintext to Server:** All messages serialize into an opaque binary envelope (`dev-opaque-v1` in development). The server stores and routes bytes only.
2. **Key Storage:** Private keys live in secure storage, never logged or exposed.
3. **Attachments:** Uploads to Cloudflare R2 are encrypted client-side before transmission. Decryption keys travel inside the encrypted message payload.

## UI Physics & Interactions

- **Consecutive Message Grouping (4px Gap):**
  - Consecutive messages from the same sender within 60s share a `4px` gap (`space-y-1`).
  - Avatar appears only on the terminal message.
  - Adjacent bubble corners flatten.
- **Message Receipts:**
  - Sent: Single checkmark `✓`.
  - Delivered: Double checkmark `✓✓` (gray).
  - Read: Double checkmark `✓✓` (Emerald `#10b981`).
- **Presence & Live Indicators:**
  - Online/offline status and typing indicators powered by Phoenix Channels.
