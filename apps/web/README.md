# ASN Web Client (`@asn/web`)

Public-facing React + TypeScript web client for the Arabian Social Network (ASN) / تواصل.

## 1. Overview & Architectural Boundaries

- **Runtime & Bundler:** React 18, TypeScript, Vite.
- **Styling & Design System:** Tailwind CSS, Radix UI Primitives, CSS Custom Properties (Multi-theme engine).
- **Fonts:** 100% Offline Local Fonts (`IBM Plex Sans Arabic` + `JetBrains Mono`) stored in `public/fonts/`. No external CDN dependencies.
- **State & Data Fetching:** TanStack Query (Server Cache, Cursor Pagination) + Zustand (UI & Session State).
- **Real-Time Delivery:** Phoenix Channels client over WebSockets for live chat, presence, and receipts.
- **Security & E2EE:** Server stores and transmits opaque binary envelopes (`dev-opaque-v1`); the browser client never transmits plaintext message bodies.

## 2. Directory Layout (`src/`)

```
src/
├── app/                  # Application routing, global providers, and layout shells
├── features/             # Domain modules (Feature-Driven Architecture)
│   ├── auth/             # Login, signup, Auth0 session handling
│   ├── feed/             # Home timeline, cursor pagination, feed filters
│   ├── posts/            # Post creation, media grid (1-4 images), long-form articles
│   ├── comments/         # Nested comment trees with interactive thread lines
│   ├── reactions/        # Optimistic likes, reposts, bookmarks
│   ├── profiles/         # User profiles, avatar customization, stats
│   ├── relationships/    # Follow, unfollow, block, friendships
│   ├── communities/      # Communities, channels, role management
│   ├── search/           # Full-text debounced search
│   ├── hashtags/         # Trending tags, hashtag timelines
│   ├── notifications/    # Notification stream, live badges
│   ├── chat/             # E2EE chat, 4px message grouping, receipts
│   └── settings/         # Theme customizer, privacy, account deletion
├── components/ui/        # Reusable headless UI primitives (Button, Input, Avatar, Dialog, etc.)
├── lib/
│   ├── api/              # Typed REST client wrapping generated contracts
│   ├── websocket/        # Phoenix Channels WebSocket client
│   ├── auth/             # Session persistence and token management
│   └── utils.ts          # Classnames merger (`cn`)
├── hooks/                # Cross-feature React hooks
├── styles/               # Design tokens, fonts, and global Tailwind layer
└── assets/               # Local static assets and brand logo
```

## 3. Local Development

```bash
# Install dependencies (from root or apps/web)
npm install

# Start Vite dev server on port 3000
npm run dev

# Typecheck and build for production
npm run build
```

## 4. Key Rules

1. **RTL First:** All spacing and positioning use CSS Logical Properties (`ms-*`, `me-*`, `ps-*`, `pe-*`, `start-*`, `end-*`). Never use physical classes (`ml-*`, `mr-*`, `left-*`).
2. **Accessible by Default:** Adhere to WCAG 2.1 AA. Never rely on color alone—pair status with icons and text.
3. **No Direct Secret Storage:** Tokens are kept in memory/secure context; never write authentication tokens to `console.log` or analytics.
