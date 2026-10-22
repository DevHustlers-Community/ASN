# Admin app

Internal staff and moderation UI.

**Owns:** staff UI state only. It is not an authorization authority.

**Primary areas:**

- Moderation queue, reports, cases, actions, appeals, bans.
- Announcements and feature-flag review.
- Audit log browsing (read-only).
- Statistics over moderation data.

**Boundaries:**

- Staff authenticate against the separate Auth0 tenant/connection with
  mandatory MFA; there is no shared session with public users.
- The app calls the Moderation API for decisions and the Social API read-only
  where needed. It never writes to `social_db`, `chat_db`, or `broker_db`.
- Viewing E2EE report evidence is an audited action; the UI must show exactly
  what is disclosed and never fetch unrelated conversation context.
- Destructive actions require confirmation and server-side role checks.

**Tests:** component tests plus contract tests against
[`contracts/openapi/moderation-api.yaml`](../../contracts/openapi/README.md).

**Status:** not scaffolded yet.
