# Architecture Decision Records

Every significant, hard-to-reverse decision gets one numbered ADR.

**Process:**

1. Copy the template below into `NNNN-short-title.md`.
2. Keep it short: context, decision, consequences, alternatives considered.
3. Record the date and status (`proposed`, `accepted`, `superseded`).
4. A decision that changes an accepted ADR links to the new ADR and marks the old
   one superseded. Never rewrite history silently.
5. If the change touches persisted formats, contracts, keys, or delivery
   semantics, link the ADR from the architecture document.

**Template:**

```markdown
# NNNN - Title

- Status: proposed
- Date: YYYY-MM-DD
- Supersedes: -

## Context

## Decision

## Consequences

## Alternatives considered
```

**Recorded ADRs:**

| ID | Subject | Status |
|---|---|---|
| [0008](0008-broker-transport-and-delivery-contract.md) | Broker transport and delivery contract | accepted |
| [0011](0011-elixir-and-postgres-baseline.md) | Elixir and PostgreSQL baseline | accepted |
| [0012](0012-frontend-design-system-and-theming.md) | Frontend design system and theming | proposed |

**Planned ADRs:**

| ID | Subject |
|---|---|
| 0001 | Monorepo layout and ownership boundaries |
| 0002 | Bun + TypeScript for Social and Moderation APIs |
| 0003 | Elixir/Phoenix for the Chat service |
| 0004 | Custom Elixir/OTP event broker instead of an off-the-shelf broker |
| 0005 | PostgreSQL as first broker storage |
| 0006 | React Native mobile client and encrypted local SQLite |
| 0007 | E2EE protocol selection (Signal/Sesame vs MLS) |
| 0009 | Opaque envelope contract from day one |
| 0010 | Web E2EE parity policy |

**Status:** 0008 and 0011 are accepted. 0012 is proposed. 0001-0006 are effectively settled
by the architecture document and should be recorded next. 0007, 0009, and 0010 remain open.

