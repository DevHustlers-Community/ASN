# Apps

Client applications. All clients consume REST APIs through generated types from
[`contracts/`](../contracts/README.md); none of them is a security boundary.

| App | Stack | Users | Talks to |
|---|---|---|---|
| [`web/`](web/README.md) | React + TypeScript | Public | Social, Chat, Moderation |
| [`mobile/`](mobile/README.md) | React Native + TypeScript | Public | Social, Chat, Moderation |
| [`admin/`](admin/README.md) | React + TypeScript | Staff | Moderation (primary), Social (read) |

Rules that apply to every app:

- Never embed server secrets, service credentials, or moderation bypass flags.
- Never enforce authorization, plan limits, or visibility rules client-side only.
- No plaintext chat content is sent to the server. Clients build an opaque
  envelope even before real E2EE ships (`dev-opaque-v1`, see
  [architecture §0.13](../docs/architecture/architecture-and-schema.md)).
- Shared code is limited to generated API types and small utilities. UI
  components are not shared between web and native.
