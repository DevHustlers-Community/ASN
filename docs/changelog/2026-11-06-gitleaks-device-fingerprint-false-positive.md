---
date: 2026-11-06
type: fix
scope: security
summary: Stop gitleaks flagging the chat device-registration fingerprint example
breaking: false
adr: -
contracts: contracts/events/examples/valid-chat-device-registered.json
---

# Stop gitleaks flagging the chat device-registration fingerprint example

## Change

- Replaced the example value of `identity_key_fingerprint` in
  [`valid-chat-device-registered.json`](../../contracts/events/examples/valid-chat-device-registered.json)
  from `FP-1A2B-3C4D-5E6F` to `placeholder`. The schema constrains the field to
  a string and imposes no pattern, so the example stays valid.
- Added [`.gitleaksignore`](../../.gitleaksignore) with the exact fingerprint of
  the historical finding in commit `ee5cf70`, so the full-history scan on `main`
  stops reporting the old value. The file explains that the value is a
  client-derived verification fingerprint, not a credential.
- Documented the rule in [`/.github/README.md`](../../.github/README.md):
  a reviewed false positive is ignored by exact fingerprint, never by excluding
  a file or disabling a rule.

## Why

The `gitleaks` job on `main` scans the whole history. The example value had
Shannon entropy 3.69 and sat next to the keyword `key`, so the `generic-api-key`
rule classified it as a leaked API key. Nothing about the value is secret: it is
public, client-derived device metadata. Editing the file alone cannot fix the
job, because the finding lives in commit `ee5cf70`, which history scans still
visit. The starting `FP-1A2B-…` shape (and its entropy) also made every future
scan of that commit fail, so the example now uses a plain placeholder.

## Verification

- `gitleaks git . --redact --verbose --exit-code 1` with gitleaks 8.30.1 — 79
  commits scanned, no leaks, exit 0 (this is the push-to-`main` path that was
  failing).
- Negative check: moved `.gitleaksignore` aside and reran the same command — one
  finding, exit 1. Restored it — no leaks, exit 0. The entry is precise and
  necessary.
- `python3 scripts/contracts/validate.py --base-ref upstream/main` — both
  OpenAPI files OK, 5 event schemas, 6 valid and 4 invalid examples (the edited
  fixture is still one of the valid ones).
- `python3 scripts/ci/check-links.py` — OK.
- `python3 scripts/ci/check-changelog.py --all` — OK.
- `gitleaks dir .` reports seven findings, all in untracked local files
  (`SSS.md` is gitignored; the rest are `deps/` checkouts of Phoenix and
  plug_crypto). CI uses `gitleaks git`, which scans committed history only, so
  those paths are out of scope.

## Follow-ups

- Demo values that look like keys should avoid the `*_key*` keyword plus
  high-entropy value combination in future fixtures.
