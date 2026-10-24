# Application Shell (`src/app`)

**Status:** initial scaffolding in `App.tsx`; product routes are proposed.

Owns the root orchestration of the web client: routing, context providers, and responsive page shells.

## Responsibilities

1. **Routing (`react-router-dom` — proposed routes):**
   - Public Routes: Landing, Login, Signup.
   - Proposed Feature Routes: Feed (`/`), Communities (`/c/:slug`), Chat (`/chat`), Profile (`/u/:username`), Settings (`/settings`).
   - Route Guards: Verify authenticated session before rendering protected feature layouts.
2. **Global Providers:**
   - `QueryClientProvider` (TanStack Query): In-memory caching, window focus refetching, retry logic (planned).
   - `ThemeProvider`: Manages `data-theme` (`oled`/`dim`/`light`) and `data-accent` (`emerald`/`indigo`/`amber`/`crimson`/`cyan`) on the `<html>` root (baseline demo active in `App.tsx`).
3. **Layout Components:**
   - `RootLayout`: Three-column responsive grid (Sidebar navigation, Main feed content, Right contextual widgets).
