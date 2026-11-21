---
date: 2026-11-22
type: feat
scope: chat
summary: Add ADR 0017 and opaque MLS KeyPackage upload under the devices context
breaking: false
adr: 0017
contracts: contracts/openapi/chat-api.yaml
---

# KeyPackage upload and ADR 0017

## Change

- Added accepted [ADR 0017](../decisions/0017-keypackage-storage-before-library-gate.md). It resolves the internal conflict in ADR 0007: decision 9 permits opaque backend storage before the client library gate, while the schema impact table marked `device_key_packages` as blocked. ADR 0017 allows storage before the gate and amends only that table row; the MLS selection in ADR 0007 is unchanged.
- Scope is deliberately **upload and metadata listing only**. Atomic claim is deferred until `blocks/` enforces block/ban status on claim and service-level rate limiting exists. No claim operation was added to the contract.
- `contracts/openapi/chat-api.yaml` adds `POST /devices/{deviceId}/key-packages` (`chat:devices`) and `GET /devices/{deviceId}/key-packages` (`chat:read`), plus `UploadKeyPackageRequest` and `KeyPackageView`. The `chatBearer` description was updated from "provisional" to the final ADR 0016 policy, and `authorization_unavailable` was added to `ErrorCode` by the authentication change. All changes are additive within version 1.0.0.
- Added migration `20261122000001_create_device_key_packages.exs` with opaque `key_package bytea`, a SHA-256 digest, a uint16 `ciphersuite` CHECK, an expiry CHECK, a size CHECK, a unique `(device_id, key_package_sha256)` index, and a partial unconsumed index reserved for the future claim path. No plaintext column, no private key material, no cascade delete.
- Added `AsnChat.Devices.KeyPackage` and extended `AsnChat.Devices` with `upload_key_package/5` and `list_key_packages/2`. Ownership, active-device status, the 90-day expiry window, the configured per-device cap, and digest computation stay in the context. No outbox event is written because no KeyPackage event contract exists.
- Added `AsnChatWeb.KeyPackageController` and two `/api/v1` routes. The controller decodes base64 at the edge and returns metadata only; KeyPackage bytes are never included in a response in this slice.
- The per-device cap counts only unexpired, unconsumed packages. With claim deferred there is no consumption or garbage collection, so counting expired rows would permanently block a device; ADR 0017 §5 records this clarification.
- The byte cap is unified at 131072 decoded bytes (174764 base64 characters), leaving room for JSON overhead under the 256 KiB whole-body limit.
- Updated architecture §3.8 with the finalized column list, the Chat README and CODE_MAP (`devices/` remains the owner), `contracts/openapi/README.md`, the decisions index, ADR 0007's amended row, and ROADMAP. The slice-one HTML reference was explicitly marked as a frozen historical snapshot; its slice-one content was left unchanged instead of being partially rewritten.

## Why

ADR 0007 selected MLS but left both the client library gate and the KeyPackage storage timing ambiguous. AGENTS.md §2 forbids resolving that silently. The user chose a new ADR and an upload-only slice so Chat can accept public protocol material without shipping an unguarded claim path while `blocks/` and rate limiting are still open.

## Verification

- `mix format --check-formatted` — clean
- `mix compile --warnings-as-errors` — clean
- `mix test` — the full Chat suite (151 tests) passes against local PostgreSQL 18.6
- `scripts/contracts/validate.py` — contracts validation OK
- `scripts/ci/check-links.py` and `scripts/ci/check-changelog.py --all` — OK

## Follow-ups

- Atomic one-time claim with distinct-bundle concurrency tests (ADR 0017).
- Block/ban enforcement on both upload and claim once `chat_block_edges` lands.
- Per-device and per-caller rate limits; the current cap is a storage bound, not a request-rate control.
- `last_resort` consumption policy and expiry retention for consumed packages.
- Reuse the vetted UUIDv7 library once architecture §9 item 16 is decided.
