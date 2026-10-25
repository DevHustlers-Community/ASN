# AGENTS.md

Instructions for AI coding agents working in the ASN repository. Read this file
before changing code, contracts, or documentation. It is agent-agnostic: any
tool that reads `AGENTS.md` gets the same rules.

## 1. Project

ASN (Arabian Social Network) is an open-source social platform with posts,
communities, real-time chat, and end-to-end encrypted messaging.

**Current state:** architecture and incremental service scaffolding. The Chat
service and Event broker have Elixir manifests, pin Elixir 1.20.4/OTP 29.1.2,
compile, and run against PostgreSQL 18.6. The web client (apps/web) and shared TypeScript presets (packages/config-typescript) are scaffolded under Bun 1.4.4. There are no product endpoints, OpenAPI or event contracts, migrations, or backend TypeScript service manifests yet. Do not assume a product feature is runnable.

**License:** AGPL-3.0.

## 2. Source of truth

Read in this order before making a change:

| Priority | Source | Use it for |
|---|---|---|
| 1 | [`docs/architecture/architecture-and-schema.md`](docs/architecture/architecture-and-schema.md) | Stack, ownership, contracts, data model |
| 2 | [`docs/decisions/`](docs/decisions/README.md) | Accepted decisions (ADRs) and their rationale |
| 3 | [`docs/GLOSSARY.md`](docs/GLOSSARY.md) | Domain vocabulary, field meanings, disambiguations |
| 4 | [`docs/changelog/`](docs/changelog/README.md) | Per-commit change records and format |
| 5 | [`contracts/openapi/`](contracts/openapi/README.md), [`contracts/events/`](contracts/events/README.md) | API and event payloads; versioning in [`contracts/VERSIONING.md`](contracts/VERSIONING.md) |
| 6 | Service/app `README.md` | Ownership, boundaries, local development, status |
| 7 | [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md) | Workflow and disclosure rules |

Rules:

- An accepted ADR wins over prose. If the architecture document contradicts an
  ADR, stop and report the conflict; do not pick one silently.
- Use [`docs/GLOSSARY.md`](docs/GLOSSARY.md) for domain terms and never invent a
  synonym for an existing concept (for example do not use "thread" for
  conversation or "group" for community).
- Every content commit needs a record under `docs/changelog/` and a
  `Changelog: docs/changelog/<record>.md` trailer. Merge commits and commits that
  only edit `docs/changelog/` are exempt.
- If a requirement is missing or ambiguous, ask or propose an ADR. Do not invent
  product behavior, schema fields, or contracts.
- Never reintroduce a technology, service, or database that is not in the stack
  table below.

## 3. Stack (fixed)

| Layer | Technology | Database |
|---|---|---|
| Social API | Bun + TypeScript, REST | `social_db` |
| Chat service | Elixir + Phoenix + Ecto, REST + WebSockets | `chat_db` |
| Moderation API | Bun + TypeScript, REST | `moderation_db` |
| Event broker | Custom Elixir/OTP + Ecto, PostgreSQL-backed, transport-neutral | `broker_db` |
| Web and admin | React + TypeScript | - |
| Mobile | React Native + TypeScript | encrypted local SQLite |
| Object storage | S3-compatible (R2) | - |

`broker_db` is owned by the broker service. No other service reads or writes it.

Local development pins Elixir 1.20.4 on OTP 29.1.2 via [`.tool-versions`](.tool-versions),
Phoenix 1.8.16 for Chat, and PostgreSQL 18.6 via [`compose.yaml`](compose.yaml).
Service lockfiles pin the resolved dependency versions.

## 4. Repository map

| Path | Contents |
|---|---|
| `apps/web`, `apps/mobile`, `apps/admin` | Clients |
| `services/social-api`, `services/chat-service`, `services/moderation-api`, `services/event-broker` | Backends |
| `contracts/openapi`, `contracts/events` | API and event contracts |
| `packages/` | Shared TypeScript tooling and generated clients |
| `infrastructure/` | Docker, proxy, databases, broker ops, observability, deployment |
| `tests/` | Cross-service integration, contract, and end-to-end tests |
| `scripts/` | Developer and CI helpers |
| `docs/` | Architecture, decisions, security, development, operations |

Every folder has a `README.md`. When you add a folder that represents an
ownership boundary or a navigable section, add or update its README in the same
change. Do not create README stubs for leaf utility folders.

## 5. Non-negotiable rules

### Architecture and data

- **One service owns one database.** Never read or write another service's
  database. No cross-database foreign keys, joins, or transactions.
- Cross-database IDs are soft references documented as
  `ref: <db>.<table>.<column>`.
- **REST only** for HTTP APIs. No GraphQL, no gRPC. The broker is for
  asynchronous events only and never replaces a synchronous response.
- **WebSockets are live delivery only.** Durable history and reconnect recovery
  always go through REST with a stable cursor.
- **Transactional outbox:** write the business change and its event in the same
  transaction. Publish only after commit.
- **At-least-once delivery:** consumers deduplicate on `event_id` and reject
  stale updates with `aggregate_version`. Never promise or assume exactly-once.
- **Per-aggregate ordering only.** No global event ordering.
- **No global business service and no global writer.** Message sequence is
  serialized per conversation (`UPDATE conversations ... last_seq`), never
  across the platform.
- The broker is a custom Elixir/OTP service. Do not add an off-the-shelf broker
  or a broker framework.
- Migrations belong to the owning service. Forward-only in production; add,
  backfill, switch, then remove.

### E2EE and security

- **No plaintext chat content anywhere on the server:** not in columns, DTOs,
  events, logs, traces, analytics, push payloads, error messages, fixtures, or
  test snapshots. Only opaque envelopes.
- There is no temporary plaintext field. Development uses `dev-opaque-v1`, which
  has the same envelope shape as production.
- Private identity, session, prekey, and backup keys never reach the server.
  Only public protocol material is stored.
- The server cannot inspect encrypted message or attachment plaintext. Do not
  promise server-side content or malware scanning for E2EE media.
- Push notifications are generic ("New message"). No previews, names, or content.
- Report evidence for an E2EE message is exactly what the reporter submitted,
  with provenance and a content hash. It is audited and never expanded with
  unrelated history.
- Authorization is enforced server-side. The client is never the authority for
  ownership, permissions, membership, or moderation status.
- Never commit secrets, tokens, keys, or real user data. Only `.env.example` with
  safe placeholders. Do not log secrets.
- Never weaken authentication, authorization, validation, or encryption to make
  a test pass.

### Data conventions

- UUIDv7 generated in application code, one vetted library per runtime.
- `timestamptz` in UTC; use `created_at`, `updated_at`, `deleted_at`.
- Enumerations as `text` + `CHECK`, kept in sync with the audit table in the
  architecture document (§8).
- Conditional uniqueness uses partial unique indexes, not table constraints
  with `WHERE`.
- Counters are denormalized, asynchronously maintained, and rebuildable.
- Do not rely on `ORDER BY id` matching `ORDER BY created_at`.
- Do not use row-level `CHECK` constraints to validate rows in another table.

## 6. How to make a change

1. **Locate the owner.** Identify the service/app and module. If a change spans
   ownership boundaries, it needs a contract and possibly an ADR.
2. **Read first.** Architecture section, relevant ADR, contract, and the owning
   README.
3. **Check open decisions.** If the change depends on an item in §9 of the
   architecture document, do not guess. Propose an ADR and ask.
4. **Contract first.** API or event changes update `contracts/` before code.
   Regenerate clients; never hand-edit generated code. Any change to an
   endpoint (path, method, request/response shape, status code, auth, or
   error code) must also update the OpenAPI/Swagger contract under
   `contracts/openapi/` and keep its rendered documentation (the local
   Swagger UI viewer) in sync; an endpoint change is not complete until the
   contract and its rendered documentation are updated.
5. **Implement inside the owner.** Keep domain rules in the service layer, not in
   route handlers, UI, or shared packages.
6. **Update docs in the same change** when behavior, boundaries, commands,
   configuration, or contracts change.
7. **Add a change record.** Create `docs/changelog/YYYY-MM-DD-slug.md` from the
   template, stage it with the change, and add the `Changelog:` trailer. Do not
   put secrets, plaintext, or real user data in it.
8. **Verify** with the checks in §7. Report what you ran and what you could not.

### TypeScript service module shape

For Social and Moderation APIs, a module is typically:

```
modules/<domain>/
├── routes.ts        # HTTP registration only
├── controller.ts    # Request/response mapping
├── service.ts       # Business rules and orchestration
├── repository.ts    # Database access
├── schemas.ts       # Input/output validation
├── policies.ts      # Authorization, when needed
└── errors.ts        # Domain errors
```

Not every module needs every file. Do not put business logic in `routes.ts`,
`controller.ts`, or a shared `shared/` folder.

### Elixir/Phoenix shape

Chat code lives under contexts: `accounts`, `conversations`, `messages`,
`attachments`, `read_receipts`, `devices`, `crypto`, `blocks`, `delivery`,
`events`. Web code lives in `asn_chat_web` (controllers, channels, plugs).
Contexts own business rules; controllers and channels are thin.

### Clients

- Web and native do not share UI components or business rules.
- Types come from generated contracts.
- Mobile: plaintext exists only inside the encrypted SQLite database; keys live
  in Keychain/Keystore, never AsyncStorage. Backups use `VACUUM INTO`, local
  encryption, then upload.
- No client-side-only authorization.

## 7. Verification

Detect commands from manifests; do not invent them.

| Area | Expected command | Status |
|---|---|---|
| JS/TS (web) | `bun install --frozen-lockfile && bun run typecheck && bun run test && bun run build:web` | Available for `apps/web` |
| Elixir (Chat) | `cd services/chat-service && mix deps.get && mix format --check-formatted && mix compile --warnings-as-errors && mix test` | Available; `mix test` requires local PostgreSQL |
| Elixir (broker) | `cd services/event-broker && mix deps.get && mix format --check-formatted && mix compile --warnings-as-errors && mix test` | Available; `mix test` requires local PostgreSQL |
| Local PostgreSQL | `docker compose up -d postgres`; wait for `healthy` | Available |
| Contracts | validation and client generation via `scripts/contracts/` | Not implemented |
| Change records | `python3 scripts/ci/check-changelog.py --all`; `python3 scripts/ci/check-commit-trailer.py <msg-file>` | Available |
| Docs | `python3 scripts/ci/check-links.py`; no contradictory statements | Available |

If a required command or script does not exist, say so. Add it only when the
task needs it, and document it in the relevant README.

Always run the checks that exist. Never claim a test passed if it was not run.

### Required test coverage for new behavior

- Unit tests in the owning service or app.
- Integration tests against a real PostgreSQL instance for database behavior.
- Contract tests when an API or event changes.
- Failure paths where relevant: duplicate and out-of-order events, broker
  restart, consumer lag, revoked device, membership removal, expired upload,
  prekey race, account deletion during an active report.

E2EE tests use fixed envelope vectors. Never add plaintext fixtures to server
tests.

## 8. Documentation rules

- [`docs/architecture/architecture-and-schema.md`](docs/architecture/architecture-and-schema.md)
  describes the current design only. Do not add changelogs, version history, or
  stack comparisons to it.
- Decisions and rationale go in numbered ADRs under `docs/decisions/`, using the
  template in that folder's README.
- An ADR is required for changes to service boundaries, protocols, persistence,
  authentication/authorization, broker semantics, E2EE protocol, or client
  storage.
- Keep each service/app README focused on purpose, ownership, boundaries, local
  development, tests, and status.
- Documentation is English. User-facing copy follows product requirements.

## 9. Git and review

- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- Branch naming and workflow follow [`CONTRIBUTING.md`](CONTRIBUTING.md).
- Every content commit includes a staged change record and a `Changelog:` trailer.
- Do not commit unless explicitly asked.
- Do not force-push, rewrite shared history, or commit generated artifacts that
  the project does not track.
- Keep changes focused; do not reformat or refactor unrelated code.
- Never merge a pull request or create a release.

## 10. Open decisions - do not resolve silently

These must be settled by an ADR before implementation depends on them. Full list
in §9 of the architecture document.

- E2EE protocol and libraries for React Native and web (Signal/Sesame vs MLS).
- Web E2EE parity timing.
- Broker transport (HTTP polling vs persistent connection), retention, and limits.
- TypeScript HTTP framework, query layer, validation, and migration tooling.
- React Native SQLite library, SQLCipher support, and key handling.
- Backup recovery method (recovery key, passphrase, passkey wrapping).
- Group key rotation and pre-join history policy.
- Types of metadata that remain server-visible.
- Report evidence retention and deletion holds.
- UUIDv7 library per runtime.

## 11. When in doubt

1. Prefer the narrower change that preserves ownership boundaries.
2. Prefer the contract-first, additive change.
3. Prefer stopping and asking over guessing on security, E2EE, or data ownership.
4. Report assumptions explicitly in your response and in the PR description.
