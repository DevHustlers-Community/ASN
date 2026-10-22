# Mobile app

React Native + TypeScript client for Android and iOS.

**Owns:** local SQLite database, outgoing queue, sync cursors, device key state,
and local UI state. Everything else is a projection of server data.

**Planned layout (`src/`):**

| Path | Purpose |
|---|---|
| `app/navigation/` | Navigators and deep links |
| `app/providers/` | Root providers |
| `app/screens/` | Screen composition only |
| `features/` | auth, feed, posts, profiles, relationships, communities, search, notifications, chat, settings |
| `features/chat/storage/` | SQLite access, migrations, snapshot/backup |
| `features/chat/services/` | Envelope construction, sync, send queue |
| `components/` | Native-only UI primitives |
| `lib/api/`, `lib/websocket/`, `lib/auth/` | Transport and session |
| `theme/` | Design tokens for native |

**Local storage rules:**

- Conversation history is stored as plaintext **only inside an encrypted SQLite
  database**; the key lives in Keychain/Keystore, never in AsyncStorage.
- Backup uses a `VACUUM INTO` snapshot, then local encryption, then Drive upload
  ([architecture §3.19](../../docs/architecture/architecture-and-schema.md)).
- The server stores ciphertext only; the server never receives backup content or
  recovery secrets.

**Boundaries:** no service credentials; no client-side-only authorization;
restoring history must not clone the old device's private identity keys.

**Tests:** unit tests beside features; device/emulator flows in
[`tests/end-to-end`](../../tests/README.md). Backup/restore has an explicit failure
test list (lost phone, corrupted snapshot, wrong recovery secret).

**Status:** not scaffolded yet. Expo vs bare React Native and the SQLite library
are open ADR decisions.
