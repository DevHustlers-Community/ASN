# Architecture

| Document | Status |
|---|---|
| [`architecture-and-schema.md`](architecture-and-schema.md) | Target architecture and schema |

**Reading order for new contributors:**

1. Stack and ownership: §0 and §1.1.
2. Service integration: §1.5, §1.6, and the event catalog (§7).
3. Chat and E2EE: §3.9, §3.10, §3.19, and the open decisions (§9).
4. Client platforms: §1.9 and the mobile README.

**Conventions for this folder:**

- This folder describes the current design only. The reasoning behind each
  decision lives in [`../decisions/`](../decisions/README.md).
- Diagrams are Mermaid and live next to the text they describe.
- Schema changes are proposed here first, then implemented as service
  migrations.
- Anything still undecided belongs in §9 and must be resolved by an ADR in
  [`../decisions/`](../decisions/README.md), not by a service implementation.
