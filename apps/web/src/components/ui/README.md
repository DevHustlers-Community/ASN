# Core UI Primitives (`src/components/ui`)

Headless, accessible UI building blocks built on Radix UI and Tailwind CSS.

## Current (Implemented Primitives)

| Component | File | Underlying Primitive | Key Variants | Status |
|---|---|---|---|---|
| `Button` | `button.tsx` | `@radix-ui/react-slot` | `default`, `secondary`, `outline`, `ghost`, `destructive`, `link` | Implemented |
| `Input` | `input.tsx` | Native HTML5 | Supports start/end icon slots, error alert, RTL alignment | Implemented |
| `Avatar` | `avatar.tsx` | `@radix-ui/react-avatar` | Online/Offline presence indicator, initials fallback | Implemented |
| `Badge` | `badge.tsx` | Custom CVA | `default`, `secondary`, `success`, `destructive`, `warning`, `info` | Implemented |

## Planned Primitives

| Component | Planned File | Planned Underlying Primitive | Purpose | Status |
|---|---|---|---|---|
| `Dialog` | `dialog.tsx` | `@radix-ui/react-dialog` | Modal with backdrop blur and accessible focus trapping | Planned |
| `Tabs` | `tabs.tsx` | `@radix-ui/react-tabs` | Underline and pill style tabs with brand accent | Planned |
| `DropdownMenu` | `dropdown-menu.tsx` | `@radix-ui/react-dropdown-menu` | Context and action menus | Planned |

## Engineering Rules

- **No Hardcoded Hex/RGB:** Every component strictly uses semantic tokens (`bg-primary`, `bg-card`, `border-border`).
- **WCAG 2.1 AA Compliance:** Minimum 4.5:1 text contrast ratio. Never rely on color alone.
- **Logical Properties Only:** Use `ms-`, `me-`, `ps-`, `pe-`, `text-start`, `text-end`.
