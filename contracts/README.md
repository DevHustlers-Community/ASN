# Contracts

The single source of truth for communication between services and clients.

| Folder | Contents |
|---|---|
| [`openapi/`](openapi/README.md) | REST API contracts, one file per REST service or HTTP transport |
| [`events/`](events/README.md) | Versioned JSON Schema event payloads and the shared envelope |
| [`VERSIONING.md`](VERSIONING.md) | Versioning, compatibility, and deprecation rules |

**Rules:**

- Contract changes land before code changes, and CI validates them.
- Versioning and deprecation follow [`VERSIONING.md`](VERSIONING.md).
- Every contract change has a change record under
  [`docs/changelog/`](../docs/changelog/README.md).
- Breaking changes require a new version (`v2` path or `*.v2.schema.json`);
  additive compatible changes stay in the current version.
- Generated clients and types are produced from here. Do not hand-maintain
  duplicates in `packages/api-client` or in apps.
- Schemas never contain plaintext chat content, private keys, recovery secrets,
  or raw backup data.
- A contract change that affects persisted state requires an ADR first.

## Validation

[`scripts/contracts/validate.py`](../scripts/contracts/validate.py) validates the
OpenAPI documents, resolves every `$ref`, checks the broker `EventEnvelope`
against the shared envelope schema, and validates the event examples under
[`events/examples/`](events/examples/README.md), including binding each valid
example's `payload` to the schema named by its `type` and `schema_version`. On
pull requests it also rejects a removed path, operation, or required field that
does not bump `info.version`.

Run it locally with the pinned tooling in
[`scripts/contracts/`](../scripts/contracts/README.md); CI runs the same entry
point from [`.github/workflows/contracts.yml`](../.github/workflows/contracts.yml)
whenever `contracts/` or `scripts/contracts/` changes.
