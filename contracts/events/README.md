# Event contracts

Versioned JSON Schema payloads plus the shared envelope.

```
events/
├── common/event-envelope.schema.json
├── social/*.v1.schema.json
├── chat/*.v1.schema.json
└── moderation/*.v1.schema.json
```

**Envelope (common fields):** `event_id`, `type`, `schema_version`,
`occurred_at`, `aggregate_type`, `aggregate_id`, `aggregate_version`, `trace_id`,
`payload`.

**Rules:**

- `event_id` is stable across outbox retries and broker redelivery.
- `aggregate_version` is monotonic per aggregate; consumers reject older values.
- Payloads carry identifiers and small deltas only. Large content uses a
  claim-check reference, never an inline blob.
- No decrypted message content, private keys, recovery secrets, or backup data.
- Additive changes keep the version; breaking changes publish a new schema file
  and a migration note.
- Every event listed in
  [the event catalog](../../docs/architecture/architecture-and-schema.md)
  gets a schema before its producer is implemented.

**Status:** the envelope schema has landed
([`common/event-envelope.schema.json`](common/event-envelope.schema.json)).
Per-event payload schemas land before their producers are implemented.

## Transport notes ([ADR 0008](../../docs/decisions/0008-broker-transport-and-delivery-contract.md))

- The publisher identity is the authenticated service credential, never a body
  field.
- The broker stores a SHA-256 `content_hash` over the complete canonical
  envelope serialization. A repeated `event_id` with identical content and
  publisher is a duplicate (200); with any differing effective field or
  publisher it is a conflict (409).
- The request body limit is 256 KiB (the whole HTTP request body), enforced at
  the transport adapter before parsing; larger content travels by claim-check
  reference inside the payload.
- Consumers must be idempotent: deduplicate on `event_id` and reject stale
  `aggregate_version` values in their own database, atomic with the business
  effect.
