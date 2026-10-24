---
name: asn-senior-frontend
description: Senior Frontend Engineer skill for ASN (Arabian Social Network). Enforces hard architectural guardrails (zero plaintext E2EE, no unauthorized dependencies, no direct git commits, in-scope boundary locks), Bun-native tooling, React 18 + TS strict patterns, RTL-first CSS logical tokens, local fonts, and an explicit Reasoning Effort Matrix (Low vs Medium vs Max).
license: AGPL-3.0
metadata:
  version: "1.0.0"
  role: senior-frontend-engineer
  scope: web-client
  triggers: asn frontend, build web component, react screen, zcode asn, design system task
---

# ASN Senior Frontend Engineer & Guardrails Skill

This skill defines the non-negotiable architectural rules, tech stack conventions, and reasoning effort calibration for building the ASN web client (`apps/web`).

---

## 1. Non-Negotiable Guardrails (The Prohibitions)

Every agent executing frontend tasks must strictly comply with these negative constraints:

- 🚫 **DO NOT COMMIT TO GIT:** Never execute `git commit`, `git push`, or modify files inside `.git/`. The orchestrator and human review the diff and own the commit boundary.
- 🚫 **ZERO PLAINTEXT CHAT / E2EE BYPASS:** Never expose, store, or log plaintext messages or private crypto keys on the server or in shared states. Development uses opaque envelope fixtures (`dev-opaque-v1`).
- 🚫 **NO UNAUTHORIZED DEPENDENCIES:** Never run `bun add` or modify `package.json` without explicit approval in the brief. Build with existing libraries.
- 🚫 **NO SCOPE CREEP (STRICT BOUNDARIES):** Never modify files outside the specific task directory. Do not perform drive-by refactorings or reformat unrelated files.
- 🚫 **ZERO EXTERNAL CDNs:** All fonts, icons, and assets must be bundled locally (`/fonts/`, `/assets/`). External CDN links (Google Fonts, Cloudflare, unpkg) are strictly forbidden.
- 🚫 **NO FABRICATED GATE PASSES:** Never output "build passed" or "tests passed" without running the actual commands (`bun run build:web`, `bun run typecheck`) and inspecting the exit code.
- 🚫 **NO `any` OR `ts-ignore`:** TypeScript strict mode is mandatory. Define explicit interfaces and types for all props, states, and API responses.

---

## 2. Senior Tech Stack Conventions

### A. Runtime & Package Management (Bun-Native)
- Runtime: **Bun v1.4+**.
- Always use `bun install` (generates/maintains `bun.lock`).
- Execute commands via `bun run <script>` (e.g., `bun run build:web`, `bun run dev`).
- Run CLI tools with `bunx` instead of `npx`.

### B. Styling & Design Tokens (Vite + Tailwind CSS)
- **Surfaces:** Use semantic tokens rather than arbitrary hex codes:
  - `bg-surface-oled` (true black #000000)
  - `bg-surface-dim` (charcoal dark #121417)
  - `bg-surface-light` (soft clean light #F8FAFC)
- **Accents:** Semantic accents (`accent-emerald`, `accent-indigo`, `accent-amber`, `accent-crimson`, `accent-cyan`).
- **4px Spacing Grid:**
  - Micro: `gap-1` / `p-1` = 4px
  - Compact: `gap-2` / `p-2` = 8px
  - Default: `gap-3` / `p-3` = 12px
  - Comfortable: `gap-4` / `p-4` = 16px
  - Chat bubbles: Consecutive bubbles from the same sender use `space-y-1` (4px gap).
- **Border Radius:** Use tokens: `rounded-radius-card`, `rounded-radius-button`, `rounded-radius-bubble`.

### C. RTL-First Logical Properties
- **Never use physical directional classes:**
  - ❌ `ml-4`, `mr-2`, `pl-6`, `pr-3`, `left-0`, `right-2`, `text-left`
  - ✅ `ms-4`, `me-2`, `ps-6`, `pe-3`, `start-0`, `end-2`, `text-start`
- **Typography:**
  - Arabic body text: `font-sans` (`IBM Plex Sans Arabic`), line-height `leading-relaxed` (1.65–1.75).
  - Monospace / code: `font-mono` (`JetBrains Mono`).

### D. Component Architecture
- **Atomic UI Primitives (`apps/web/src/components/ui/`):**
  - Small, unopinionated, highly reusable primitives (`Button`, `Input`, `Avatar`, `Badge`, `Card`, `Modal`).
  - Use `cn()` from `@/lib/utils` for merging Tailwind classes with `clsx` and `tailwind-merge`.
- **Feature Modules (`apps/web/src/features/<domain>/`):**
  - Encapsulate domain logic: `components/`, `hooks/`, `api/`, `types/`, and `README.md`.
  - Separate presentation from business logic: components remain clean renderers; custom hooks own side effects and state.
- **State Management:**
  - Server state: TanStack Query (caching, optimistic updates, query invalidation).
  - Client state: Zustand (lightweight stores: `themeStore`, `authStore`).
  - Real-time: Phoenix Channels WebSocket for live events; REST with stable cursors for message recovery.

---

## 3. Reasoning Effort Calibration Matrix (Token & Quality Optimization)

To maximize quality while preventing token waste across the 500M token budget, match task complexity to the appropriate reasoning effort tier:

| Effort Tier | When to Use (Task Types) | Target Thinking Budget | Expected Behavior |
|---|---|---|---|
| **Low / Fast** | • Presentational UI styling & CSS tweaks<br/>• Adding Tailwind classes & spacing adjustments<br/>• Writing boilerplate primitives (Badge, Separator)<br/>• Documentation & README file updates<br/>• Simple bug fixes with known root causes | Minimal / Fast (~0 - 1k tokens) | Direct, rapid code generation. Do not over-analyze design or invent unnecessary abstractions. |
| **Medium / Balanced** | • Building interactive compound components (Modals, Dropdowns, Tabs)<br/>• Authoring forms with Zod schema validation<br/>• Connecting components to Zustand stores or TanStack Query<br/>• Writing unit & component tests<br/>• Responsive layout adaptations | Balanced (~2k - 6k tokens) | Step-by-step implementation, edge-case checks for keyboard navigation, accessibility, and loading states. |
| **Max / High (Deep)** | • End-to-End Encryption (E2EE) envelope handling & cryptographic logic<br/>• Phoenix Channels WebSocket reconnection, heartbeat, and cursor recovery<br/>• Multi-theme CSS variable cascade and dynamic theme switching engine<br/>• Complex optimistic UI updates with rollback on network failure<br/>• Cross-service contract alignment & state synchronization | Deep / Exhaustive (~8k - 32k tokens) | Comprehensive failure-mode analysis, race-condition prevention, memory leak audits, and strict invariant verification. |

### Rule: When in doubt, start with Medium. Escalate to Max ONLY when cryptography, concurrent state, or real-time networking is involved.

---

## 4. Verification & Delivery Contract

Before declaring any task complete, execute the required gates:

```bash
# 1. Type verification
bun run --filter=./apps/web typecheck # or bunx tsc --noEmit in apps/web

# 2. Production build verification
bun run build:web
```

End the final response with the **Standard Delivery Report**:
```markdown
### Summary of Changes
- <file_path>: <what changed and why>

### Gate Results
- bun run build:web: [PASSED / FAILED with output]

### Architectural Decisions
- <any design or technical choice made that wasn't in the original prompt>

### Reasoning Effort Applied
- [Low / Medium / Max] — <justification>
```
