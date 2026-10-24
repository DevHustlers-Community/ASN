# Core UI Primitives (`src/components/ui`)

Headless, accessible UI building blocks built on Radix UI and Tailwind CSS.

## Primitives Catalog

| Component | File | Radix Underlying Primitive | Key Variants |
|---|---|---|---|
| `Button` | `button.tsx` | `@radix-ui/react-slot` | `default`, `secondary`, `outline`, `ghost`, `destructive`, `link` |
| `Input` | `input.tsx` | Native HTML5 | Supports start/end icon slots, error banner, RTL text alignment |
| `Avatar` | `avatar.tsx` | `@radix-ui/react-avatar` | Online/Offline presence dot, initials fallback |
| `Badge` | `badge.tsx` | Custom CVA | `default`, `secondary`, `success`, `destructive`, `warning`, `info` |
| `Dialog` | `dialog.tsx` | `@radix-ui/react-dialog` | Modal with backdrop blur and accessible focus trapping |
| `Tabs` | `tabs.tsx` | `@radix-ui/react-tabs` | Underline and pill style tabs with brand accent |

## Engineering Rules

- **No Hardcoded Hex/RGB:** Every component strictly uses design tokens (`bg-primary`, `bg-card`, `border-border`).
- **WCAG 2.1 AA Compliance:** Minimum 4.5:1 text contrast ratio. Never rely on color alone.
- **Logical Properties Only:** Use `ms-`, `me-`, `ps-`, `pe-`, `text-start`, `text-end`.
