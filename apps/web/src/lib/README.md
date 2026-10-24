# Library & Transport Infrastructure (`src/lib`)

**Status:** `utils.ts` implemented; transport wrappers are planned.

Core clients, transport wrappers, and utilities.

## Current (Implemented)

- **`utils.ts`:**
  - Class merger (`cn`) combining `clsx` and `tailwind-merge` for safe Tailwind class merging.

## Planned (Target Architecture)

- **`api/`:**
  - Planned REST API client wrapping generated types from `contracts/openapi/`.
  - Handles Bearer tokens, request tracing headers (`x-request-id`), and RFC 9457 error decoding.
- **`websocket/`:**
  - Planned Phoenix Channels client managing socket connection, exponential backoff reconnects, and channel subscriptions (`user:*`, `conversation:*`).
- **`auth/`:**
  - Planned session handlers and token management.
