# Contract versioning and deprecation

Applies to every REST contract in [`openapi/`](openapi/README.md) and every event
schema in [`events/`](events/README.md). A contract is a public interface between
services, clients, and the event log; compatibility is a requirement, not a
courtesy.

## Ownership and review

- The **producing service owns** its contract. Consumers review changes that
  affect them.
- Contract changes land before code, with a change record under
  `docs/changelog/`.
- `.github/CODEOWNERS` routes contract changes to the owning maintainer.
- A change to a persisted format, event semantics, or delivery contract also
  needs an ADR before implementation.

## REST APIs

- Current base path: `/api/v1`. Additive, backward-compatible changes stay in
  `v1`. Breaking changes require `/api/v2`; never break `v1` in place.
- Additive changes: new endpoints, new optional request fields, new response
  fields, and new enum values **only if** clients are documented to tolerate
  unknown values.
- Breaking changes: removing or renaming fields, changing a type or meaning,
  making an optional field required, changing status codes, or changing
  authorization behavior.
- A deprecated operation or field is marked `deprecated: true` in OpenAPI and
  returns `Deprecation` and `Sunset` headers where applicable.
- Default deprecation window for a public API is **90 days** after the
  deprecation is announced. An ADR may set a different window. Security-critical
  removals may be faster, but the reason and date are recorded publicly without
  exploit details.
- Do not reuse a removed path, field name, or enum value with a new meaning.

## Events

- Each event has a stable `type`, a `schema_version`, and the common envelope
  fields. `aggregate_version` orders business state; it is not a schema version.
- Every payload schema change increments `schema_version`. Additive changes keep
  the event type and must remain consumable by existing consumers.
- Consumers must ignore unknown fields and tolerate unknown enum values.
- Breaking changes require a **new event type** with a `.v2` suffix and a file
  named `<event>.v2.schema.json`. Dual-publish old and new types for the
  deprecation window; do not silently change the meaning of the old type.
- The event log is durable. New consumers must handle old schema versions that
  are still within retention. Removing support requires a documented retention
  and replay plan.
- Events never carry plaintext chat content, private keys, recovery secrets, raw
  backups, or evidence payloads.

## Compatibility checklist

Before merging a contract change:

- [ ] The change is additive, or a new version exists.
- [ ] OpenAPI or JSON Schema validates.
- [ ] Generated clients and types are regenerated; no hand edits.
- [ ] Consumers can ignore new fields and enum values.
- [ ] A change record names the contract and compatibility impact.
- [ ] Breaking changes link an ADR and a deprecation plan.
- [ ] Persisted-data impact is called out with a migration plan.
