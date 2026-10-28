# Roadmap

Personal working roadmap for the ASN (Arabian Social Network) project.
Status is tracked here; completed items move to the changelog.

## Done (recent)

- [x] Event broker v1 (schema, publish/fan-out, claim/lease, ack/nack/extend, dead-letter, retention, HTTP edge, metrics, telemetry)
- [x] Broker audit remediation (crashes, retention cutoffs, audit atomicity, DB-time lease checks, indexes, contract, docs)
- [x] Chat service: accounts/conversations/messages + outbox + broker relay
- [x] Web client scaffolding + design system
- [x] Local Swagger UI viewer + endpoint-doc rule

## Next (recommended order)

1. [ ] **Cross-service e2e harness** (`tests/`) — chat outbox → broker → consumer; duplicate/out-of-order/restart cases. *(highest value)*
2. [ ] **Social API scaffolding** (Bun + TypeScript) — requires ADR for HTTP framework/query/validation (open decision §9).
3. [ ] **Moderation API scaffolding** (Bun + TypeScript).
4. [ ] **Docs/README sync** — broker README "Remaining: metrics exposition" line is stale; align coverage notes.
5. [ ] **Bandit advisories follow-up** (if not bundled) — already bumped to 1.14 in broker.

## Open decisions (ADR required before implementation)

See `docs/architecture/architecture-and-schema.md` §9 and `AGENTS.md` §10:
- E2EE protocol/libraries (Signal/Sesame vs MLS)
- Broker transport/retention/limits
- TypeScript HTTP framework, query layer, validation, migration tooling
- React Native SQLite library + SQLCipher
- Backup recovery method
- Group key rotation / pre-join history
- Metadata visibility, report evidence retention
- UUIDv7 library per runtime

## Notes

- Never commit or push from the agent; user lands commits.
- Every content commit needs `docs/changelog/<record>.md` + `Changelog:` trailer.
