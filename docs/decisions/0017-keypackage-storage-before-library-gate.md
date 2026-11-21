# 0017 - KeyPackage storage before the client library gate

- Status: accepted
- Date: 2026-11-22
- Supersedes: only the `device_key_packages` gate answer in ADR 0007 §Schema impact; the MLS protocol selection in ADR 0007 remains accepted

## Context

ADR 0007 selects MLS (RFC 9420) and states in decision 9 that "the backend may
build MLS-shaped, opaque storage before the gate; it must not claim production
E2EE until the gate passes." Its schema impact table, however, marks the new
`device_key_packages` table as "Yes; add after the library gate confirms the
KeyPackage shape." `ROADMAP.md` already says the slice is "not blocked on
protocol selection."

AGENTS.md §2 requires a conflict like this to be resolved by an ADR, not by
silently choosing one sentence. The Chat service also has no `blocks/` context
and no rate limiting yet, while ADR 0007 §Risks requires block/ban enforcement
on KeyPackage upload and claim. This ADR resolves the storage question and
limits the slice so that no unguarded claim path ships.

## Decision

1. **Storage may land before the library gate.** `device_key_packages` stores
   opaque, public MLS protocol material. Nothing in this ADR claims production
   E2EE; `dev-opaque-v1` remains the development envelope until the client
   library gate in ADR 0007 passes.

2. **Upload only.** This slice implements KeyPackage upload and listing for the
   owning device. Atomic claim is explicitly deferred until `blocks/` enforces
   block/ban status on claim and service-level rate limiting exists. The
   contract gains no claim operation in this slice.

3. **Ownership stays with `AsnChat.Devices`.** The Chat service README and
   CODE_MAP already name `devices/` as the owner of MLS KeyPackage storage;
   `crypto/` remains protocol state, rotation triggers, and envelope helpers.

4. **Finalized columns.** `id uuid PK` (UUIDv7 from `AsnChat.UUIDv7`),
   `device_id uuid FK -> chat_devices (RESTRICT)`, `key_package bytea NOT NULL`
   (opaque bytes), `key_package_sha256 bytea NOT NULL`,
   `ciphersuite integer NOT NULL CHECK (ciphersuite BETWEEN 1 AND 65535)`,
   `created_at timestamptz NOT NULL`, `expires_at timestamptz NOT NULL CHECK
   (expires_at > created_at)`, `last_resort boolean NOT NULL DEFAULT false`,
   `consumed_at timestamptz NULL`. A unique index on
   `(device_id, key_package_sha256)` prevents the same bundle from being stored
   twice; a partial index on `(device_id, expires_at) WHERE consumed_at IS NULL`
   serves the future claim path.

5. **Upload rules.** `key_package` must decode to non-empty bytes and stay under
   a configured size; `expires_at` must be in the future and no more than
   90 days ahead; `created_at` is server-generated. A device may hold at most a
   configured number of valid, unconsumed packages (operational configuration,
   not a contract value). Expired packages do not count toward the cap: with
   claim deferred there is no consumption or garbage collection in this slice,
   so counting them would permanently block a device from uploading. Duplicate
   bytes are rejected, not replaced.

6. **`last_resort` is metadata only here.** Its consumption and fallback policy
   is one of the open questions in ADR 0007 and is settled together with claim,
   not by this ADR.

7. **ADR 0007 amendment.** The `device_key_packages` row of its schema impact
   table now points to this ADR. ADR 0007 itself is not superseded.

## Consequences

- Chat can accept and store public KeyPackages while the client library gate
  and Social block projection are still open.
- No caller can consume another user's KeyPackage in this slice, so the
  unauthenticated drain risk and the missing block check cannot be exercised.
- Digest uniqueness makes "one bundle, one future claim" a database invariant
  before claim code exists.
- Claim, block/ban gating on both directions, per-device/unconsumed retention,
  and last-resort policy are explicit follow-ups.
- The partial index and `consumed_at` column are stored ahead of their first
  reader because altering a persisted KeyPackage table later is more expensive
  than adding an unused nullable column now.

## Alternatives considered

- **Wait for the client library gate.** Rejected: ADR 0007 decision 9 already
  permits opaque backend storage, and waiting blocks every messaging slice.
- **Build upload and claim together.** Rejected for this slice: blocks/ and rate
  limiting do not exist, so claim would be an unguarded entry point.
- **Treat `last_resort` policy as settled now.** Rejected: ADR 0007 lists it as
  open; deciding it here would invent product behavior.
- **Put the table under `crypto/`.** Rejected: it contradicts the documented
  ownership of `devices/`; AGENTS.md requires the documented owner to win.
