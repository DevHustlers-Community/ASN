# ASN Web Client (`@asn/web`)

Public-facing React + TypeScript web client for the Arabian Social Network (ASN).

**Owns:** browser UI state and non-sensitive client cache only.

**Boundaries:**
- Consumes REST under `/api/v1/` and the Chat WebSocket channel.
- Does not read another service's database, hold service credentials, or decide
  visibility/authorization on its own.
- Chat envelopes are opaque handles; the browser never sends plaintext message
  bodies to Chat.

**Tests:** unit and component tests next to the feature or under `src/test/`; end-to-end
flows live in `tests/end-to-end`.

**Status:** scaffolded; no product routes or API integration yet.

## 1. Overview & Toolchain

- **Runtime & Package Manager:** Bun v1.4+ (`bun.lock`).
- **Framework & Bundler:** React 18, TypeScript, Vite.
- **Styling & Design System:** Tailwind CSS, CSS Custom Properties (Multi-theme engine), Radix UI primitives.
- **Fonts:** 100% Offline Local Fonts (`IBM Plex Sans Arabic` + `JetBrains Mono`) stored in `public/fonts/` with OFL licenses. No external CDN dependencies.
- **State & Data Fetching:** TanStack Query (planned for Server Cache); theme and UI currently use React `useState` (global store planned).
- **Security:** Strict E2EE boundary; planned E2EE support with opaque binary envelopes (`dev-opaque-v1`); no chat implementation or fixtures yet.

## 2. Directory Layout (`src/`)

### Current (Implemented Baseline)
```
src/
├── app/                  # Application root (App.tsx demo)
├── components/ui/        # Implemented atomic primitives (Button, Input, Avatar, Badge)
├── lib/
│   └── utils.ts          # Classnames merger (`cn`)
├── styles/               # Design tokens (tokens.css), fonts (fonts.css), globals.css
├── test/                 # Component and utility unit tests (Bun test + happy-dom)
└── main.tsx              # Application entry point
```

### Planned (Target Architecture)
```
src/
├── features/             # Domain modules (planned — no implementation yet)
│   ├── auth/             # Login, signup, session handling
│   ├── feed/             # Home timeline, cursor pagination
│   ├── posts/            # Post composer, adaptive media grid
│   ├── comments/         # Nested comments with collapsible thread lines
│   ├── reactions/        # Optimistic reactions and reposts
│   ├── profiles/         # User profiles and stats
│   ├── relationships/    # Follow, unfollow, block
│   ├── communities/      # Communities and channels
│   ├── search/           # Full-text debounced search
│   ├── hashtags/         # Trending tags and timelines
│   ├── notifications/    # Notification stream and badges
│   ├── chat/             # Chat UI with 4px consecutive message grouping
│   └── settings/         # Theme customizer and account privacy
└── lib/
    ├── api/              # Planned REST API client from generated contracts
    ├── websocket/        # Planned Phoenix Channels WebSocket client
    └── auth/             # Planned session persistence
```

## 3. Local Development

```bash
# Install dependencies
bun install

# Start Vite dev server on port 3000
bun run dev

# Run typecheck
bun run typecheck

# Run unit tests
bun run test

# Build for production
bun run build
```

If a script resolves to a Node shebang in a non-standard environment, force Bun with `bun --bun run <script>`.

## 4. Key Rules

1. **RTL First:** All spacing and positioning use CSS Logical Properties (`ms-*`, `me-*`, `ps-*`, `pe-*`, `start-*`, `end-*`). Never use physical classes (`ml-*`, `mr-*`, `left-*`).
2. **Accessible by Default (WCAG 2.1 AA):** Minimum font size is 12px (`text-xs`). Interactive elements have accessible names and states (`aria-pressed`, `aria-label`).
3. **No Plaintext or Direct Secret Storage:** Chat messages remain opaque handles; private keys never enter web storage without an accepted ADR.
