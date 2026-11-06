---
date: 2026-11-06
type: fix
scope: contracts
summary: Remove the duplicate 422 response in updateReadCursor and reject duplicate YAML keys
breaking: false
adr: -
contracts: contracts/openapi/chat-api.yaml, scripts/contracts/validate.py
---

# Remove the duplicate 422 response in updateReadCursor and reject duplicate YAML keys

## Change

- Removed the repeated `'422'` mapping under
  `updateReadCursor` in [`chat-api.yaml`](../../contracts/openapi/chat-api.yaml).
  The operation had two `422` responses: the correct one (`last_read_seq`
  exceeds `conversations.last_seq`) and a copy-pasted one describing a cursor
  bound to another resource. YAML keeps the last duplicate silently, so the
  rendered Swagger UI showed the wrong description and the correct one was
  unreachable.
- Made [`scripts/contracts/validate.py`](../../scripts/contracts/validate.py)
  parse YAML with a loader that rejects duplicate mapping keys instead of
  accepting the last value silently. The base-ref comparison uses the same
  loader.
- Documented the states the Chat slice-1 schema admits but no operation can
  reach in [`contracts/openapi/README.md`](../../contracts/openapi/README.md),
  so clients do not assume undeclared behaviour.

## Why

A duplicate status key is invisible in review and in the rendered docs: the
contract still passes OpenAPI validation and the YAML parser overwrites the
first value. The published slice therefore documented an incorrect `422` for the
read cursor. Rejecting duplicate keys turns a silent authoring mistake into a
build failure.

## Verification

- `python3 scripts/contracts/validate.py --base-ref origin/main` — both OpenAPI
  files OK, 5 event schemas, 6 valid and 4 invalid examples.
- Regression check: injected a temporary duplicate `'422'` into
  `chat-api.yaml`; the validator failed with
  `DuplicateKeyError: duplicate key '422' at line 480` (exit 1). Restored the
  file; the validator passed again (exit 0).
- Parsed the final contract: `updateReadCursor` now exposes exactly one `422`,
  described as `last_read_seq` exceeding `last_seq`, and 7 distinct response
  codes.
- `python3 scripts/ci/check-links.py` — relative documentation links OK.
- `python3 scripts/ci/check-changelog.py --all` — change records OK.

## Follow-ups

- `scripts/contracts/validate.py` still does not bind payload schemas to
  envelope `type` values.
- The coverage gaps listed in `contracts/openapi/README.md` stay open until
  their slices land; the deleted-message state needs a delete endpoint before
  clients can observe it.
