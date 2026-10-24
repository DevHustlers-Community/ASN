# Auth Feature (`src/features/auth`)

Handles user authentication, onboarding, session persistence, and logout.

## Architecture & Integration

- **Identity Provider:** Auth0 Universal Login / PKCE flow.
- **Boundaries:**
  - Client never stores plaintext passwords or secrets.
  - Access tokens reside in memory; refresh tokens travel in HttpOnly cookies where supported.
  - On 401 Unauthorized responses, triggers automated silent refresh or redirects to login.
- **Forms & Validation:**
  - Login & Register forms built with `react-hook-form` and `zod`.
  - Error messages in Arabic.
