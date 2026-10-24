# Feed Feature (`src/features/feed`)

**Status:** planned — no implementation yet.

Manages the primary timeline feeds: Home (Following), Explore (For You), and Community feeds.

## Technical Details

- **Pagination Style:** Cursor-based pagination (`useInfiniteQuery` via TanStack Query).
- **Backend Service:** `Social API` (`/api/v1/feed`).
- **Tabs:**
  - `لأجلك (For You)`: Algorithmically ranked feed.
  - `أتابعهم (Following)`: Reverse chronological posts from followed accounts.
  - `المجتمعات (Communities)`: Posts from joined communities only.
- **Scroll Restoration:** Virtualized or windowed scroll state preserved upon navigating back.
