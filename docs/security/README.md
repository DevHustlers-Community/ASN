# Security

| Document | Purpose |
|---|---|
| `threat-model.md` | Assets, actors, trust boundaries, and abuse cases |
| `authentication.md` | User and staff sessions, service credentials |
| `authorization.md` | Ownership, roles, community permissions, admin actions |
| `vulnerability-reporting.md` | How to report a vulnerability privately |

**Non-negotiable rules:**

- E2EE: the server never receives message plaintext, private keys, or backup
  recovery secrets. Envelopes are opaque.
- Every service authorizes its own resources; the client is never the authority.
- Never log or trace decrypted content, tokens, keys, or evidence payloads.
- Moderator and staff access to evidence is audited.
- Report vulnerabilities privately, never in a public issue.
- Secrets live in the deployment environment, never in the repository.

**Status:** the four documents are not written yet. The threat model is the first
one, before E2EE implementation.
