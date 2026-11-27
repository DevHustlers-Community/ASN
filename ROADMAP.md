# Roadmap

Personal working roadmap for the ASN (Arabian Social Network) project.
Status is tracked here; completed items move to the changelog.

## Done (recent)

- [x] Event broker v1 (schema, publish/fan-out, claim/lease, ack/nack/extend, dead-letter, retention, HTTP edge, `/metrics` exposition, telemetry)
- [x] Broker audit remediation (crashes, retention cutoffs, audit atomicity, DB-time lease checks, indexes, contract, docs)
- [x] Chat service: scaffold + contract slice 1 (OpenAPI, event schemas, migrations) + outbox + broker relay
- [x] Chat accounts projection lock and devices context (registration, revocation, listing, device events)
- [x] Chat REST authentication and request policy ([ADR 0016](docs/decisions/0016-rest-authentication-and-request-policy.md)): JWT verification, authoritative Social authorization check, Problem Details, body limit, and device HTTP endpoints
- [x] Cross-service e2e happy path (`tests/e2e/broker-relay.sh`): chat outbox → broker → claim → ack → metrics
- [x] Web client scaffolding + design system
- [x] Local Swagger UI viewer + endpoint-doc rule
- [x] Broker consumer-service authorization, credential expiry, subscription-create audit, and database-clock lease backoff
- [x] Chat KeyPackage **upload** ([ADR 0017](docs/decisions/0017-keypackage-storage-before-library-gate.md)): `device_key_packages` table, opaque upload endpoint, digest uniqueness, and device-owned listing. Claim is deferred.
- [x] Cross-service E2E hardening: dedicated test databases, destructive-operation guards, and a contract-valid event from the real Chat devices context

## Next (recommended order)

1. [ ] **Chat KeyPackage claim** — atomic one-time claim and concurrency tests, after `blocks/` enforces block/ban status on upload and claim and service-level rate limiting exists ([ADR 0017](docs/decisions/0017-keypackage-storage-before-library-gate.md) follow-up). Upload already landed.
2. [ ] **Chat conversations and messages** — conversation/membership contexts, per-conversation sequence issuance, opaque envelope send/history, and read cursors against the existing contract.
3. [ ] **TypeScript service stack ADR** (§9.2) — HTTP framework, query layer, validation, and migration tooling — then Social API scaffolding and `user.*` events for the `chat_users` projection.
4. [ ] **Moderation API scaffolding** after the TypeScript stack ADR.
5. [ ] **API client generation** — generator ADR, generated `packages/api-client`, CI drift check, then Web API integration.
6. [ ] **Extend the e2e harness** with duplicate, out-of-order, broker restart, and consumer-lag cases.

## Open decisions (ADR required before implementation)

See `docs/architecture/architecture-and-schema.md` §9 and `AGENTS.md` §10:
- E2EE client library gate (MLS is selected by ADR 0007; Signal/Sesame is the fallback)
- Web E2EE parity timing
- Broker partitioning/scaling thresholds
- Authorization propagation after blocks, bans, and removals
- Device identity verification and revocation propagation
- Group key rotation / pre-join history (ADR 0014 proposed)
- Backup recovery method
- React Native SQLite library + SQLCipher
- Metadata visibility, report evidence retention
- UUIDv7 library per runtime

## Notes

- Never commit or push from the agent; user lands commits.
- Every content commit needs `docs/changelog/<record>.md` + `Changelog:` trailer.
