# Application Shell (`src/app`)

Owns the root orchestration of the web client: routing, context providers, and responsive page shells.

## Responsibilities

1. **Routing (`react-router-dom`):**
   - Public Routes: Landing, Login, Signup.
   - Protected Routes: Feed (`/`), Communities (`/c/:slug`), Chat (`/chat`), Profile (`/u/:username`), Settings (`/settings`).
   - Route Guards: Verify authenticated session before rendering protected feature layouts.
2. **Global Providers:**
   - `QueryClientProvider` (TanStack Query): In-memory caching, window focus refetching, retry logic.
   - `ThemeProvider`: Manages `data-theme` (oled/dim/light) and `data-accent` (emerald/indigo/amber/crimson/cyan) on the `<html>` root.
3. **Layout Components:**
   - `RootLayout`: Three-column responsive grid (Sidebar navigation, Main feed content, Right contextual widgets).
