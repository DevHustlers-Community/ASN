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

**Status:** not written yet. The envelope schema is the first artifact to land,
before the broker proof of concept.
