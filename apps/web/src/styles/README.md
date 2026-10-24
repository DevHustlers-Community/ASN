# Typography and Style Tokens (`src/styles`)

Token definitions, local offline fonts, and global style layers.

## Files

- `fonts.css`: `@font-face` definitions pointing to local font files in `public/fonts/`.
  - Primary Arabic & Latin: **`IBM Plex Sans Arabic`** (Regular, Medium, SemiBold, Bold).
  - Monospace: **`JetBrains Mono`**.
- `tokens.css`: Semantic CSS variables for OLED, Dim, and Light modes, plus Emerald, Indigo, Amber, Crimson, and Cyan accents.
- `globals.css`: Base Tailwind directive layers with zero CDN imports.
