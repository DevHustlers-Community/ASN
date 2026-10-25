---
date: 2026-10-26
type: docs
scope: contracts
summary: Add local Swagger UI viewer for OpenAPI contracts and require endpoint doc updates
breaking: false
adr: "-"
contracts: contracts/openapi/index.html
---

# Add local Swagger UI viewer and require endpoint documentation updates

## Change

- Added `contracts/openapi/index.html`, a small local Swagger UI (v5, loaded
  from CDN) viewer that renders `contracts/openapi/event-broker-api.yaml`,
  served by any static file server (e.g. `python3 -m http.server`).
- Updated `AGENTS.md` §6 (step 4, "Contract first") to state that any change
  to an endpoint (path, method, request/response shape, status code, auth, or
  error code) must also update the OpenAPI/Swagger contract under
  `contracts/openapi/` and keep its rendered documentation in sync; an
  endpoint change is not complete until both are updated.

## Why

The project's API contracts are machine-readable OpenAPI files, but there was
no convenient way to render them for review. Adding a local Swagger UI viewer
makes contract review and endpoint changes easier to validate visually.
Recording the requirement in `AGENTS.md` keeps contract-first discipline
explicit for automated and human contributors, so endpoint changes cannot
land without updating their documentation.

## Verification

- `python3 scripts/ci/check-changelog.py --all` — run; pass (new record valid).
- `python3 scripts/ci/check-links.py` — run; pass (no broken relative links).
- Swagger UI page served locally and loads `event-broker-api.yaml` without
  console errors.

## Follow-ups

- Generate the missing `social-api.yaml`, `chat-api.yaml`, and
  `moderation-api.yaml` contracts for the first vertical slice.
- Add Spectral/Redocly lint and client-generation drift checks under
  `scripts/contracts/` (still planned).
