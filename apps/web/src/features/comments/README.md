# Comments Feature (`src/features/comments`)

**Status:** planned — no implementation yet.

Handles threaded, nested conversation hierarchies beneath posts.

## Architecture & UX

1. **Continuous Thread Lines:**
   - 2px vertical guide lines connect parent comments to child replies.
   - Hovering over a guide line highlights the entire branch.
2. **Reddit/Linear Collapsible Branches:**
   - Sleek pill button with rotating chevron.
   - Collapsing folds the entire descendant tree into a compact single-line preview:
     `💬 خيط نقاش مطوي (رد واحد من فريق ASN) · انقر لتوسيع الردود ▾`
3. **Optimistic Submissions:**
   - Submitting a reply immediately injects the comment into TanStack Query's cache with a pending status, rolling back gracefully if the API call fails.
