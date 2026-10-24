# Library & Transport Infrastructure (`src/lib`)

Core clients, transport wrappers, and utilities.

## Modules

1. **`api/`:**
   - REST API client wrapping generated types from `contracts/openapi/`.
   - Handles Bearer tokens, request tracing headers (`x-request-id`), and RFC 9457 error decoding.
2. **`websocket/`:**
   - Phoenix Channels client managing socket connection, exponential backoff reconnects, and channel subscriptions (`user:*`, `conversation:*`).
3. **`auth/`:**
   - Auth0 session handlers and token management.
4. **`utils.ts`:**
   - Class merger (`cn`) combining `clsx` and `tailwind-merge`.
