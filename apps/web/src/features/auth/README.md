# Auth Feature (`src/features/auth`)

**Status:** planned — no implementation yet.

Handles user authentication, onboarding, session persistence, and logout.

## Architecture & Integration

> **Note on Token/Session Strategy:** Token storage and session management on the web are open decisions pending an accepted ADR (architecture §9). Specific strategies described here are target proposals.

- **Proposed Boundaries:**
  - Client never stores plaintext passwords or credentials.
  - Access tokens stored in memory; refresh strategy subject to final session ADR.
  - On 401 Unauthorized responses, triggers silent refresh or redirects to login.
- **Planned Forms & Validation:**
  - Login & Register forms planned with schema validation (`zod`) and form controllers (`react-hook-form`).
  - Validation messages localized in Arabic.
