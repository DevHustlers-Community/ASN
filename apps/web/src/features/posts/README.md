# Posts & Content Feature (`src/features/posts`)

**Status:** planned — no implementation yet.

Owns post creation, post cards, media galleries, and long-form articles.

## Core Components

1. **`PostCard` (`post-card.tsx`):**
   - Author metadata, timestamp, content body with hashtag and @mention parsing.
   - **Adaptive Media Grid:** Supports 1 to 4 images:
     - 1 Image: Full-width 16:9 with maximum height constraint.
     - 2 Images: 50/50 horizontal split.
     - 3 Images: 1 large primary image + 2 stacked side images.
     - 4 Images: 2x2 uniform grid.
   - **BlurHash Placeholders:** CSS gradient placeholder during R2 asset streaming to eliminate CLS (Cumulative Layout Shift).
2. **`ArticleCard` (`article-card.tsx`):**
   - Renders long-form posts (`kind = 'article'`) with headline, estimated reading time, cover thumbnail, and reader link.
3. **`CreatePostModal`:**
   - Textarea with auto-resize, media uploader with client-side image compression, visibility options (Public / Followers / Community).
