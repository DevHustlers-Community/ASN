# Contract validation

Validate the REST and event contracts under [`contracts/`](../../contracts/README.md).

## Setup

The tooling uses Python 3.12 and the pinned packages in
[`requirements.txt`](requirements.txt):

```sh
python3 -m venv .venv
.venv/bin/pip install -r scripts/contracts/requirements.txt
```

## Run

```sh
.venv/bin/python scripts/contracts/validate.py
```

On a pull request, also compare the OpenAPI documents with the base branch:

```sh
.venv/bin/python scripts/contracts/validate.py --base-ref origin/main
```

CI runs the same entry point from
[`.github/workflows/contracts.yml`](../../.github/workflows/contracts.yml).

## Checks

| Check | Failure |
|---|---|
| OpenAPI documents | invalid OpenAPI 3.1 or an unresolved internal `$ref` |
| External `$ref` | a missing target file or JSON Pointer |
| Broker `EventEnvelope` | required fields or property names drift from the shared envelope |
| Event schemas | invalid JSON Schema |
| Payload schema names | not `<event-type>.v<version>.schema.json` |
| Payload schema `$id` | differs from the path relative to `contracts/events/` |
| `valid-*.json` payloads | rejected by the schema bound to `type` and `schema_version`, or missing for a namespace that has payload schemas |
| `valid-*.json` examples | rejected by the event envelope |
| `invalid-*.json` examples | accepted by the event envelope |
| Breaking OpenAPI changes | a removed path, operation, or required field without an `info.version` bump |

The example fixtures live in
[`contracts/events/examples/`](../../contracts/events/examples/README.md). The
script fails closed: a missing example set, an unknown filename prefix, or an
unreadable file is an error, not a skip.
