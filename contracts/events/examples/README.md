# Event envelope examples

Fixtures for [`scripts/contracts/validate.py`](../../../scripts/contracts/validate.py).

- `valid-*.json` must satisfy
  [`../common/event-envelope.schema.json`](../common/event-envelope.schema.json).
- `invalid-*.json` must be rejected by that schema.
- Any other filename prefix is an error, so a fixture cannot be silently
  ignored.

The examples carry identifiers and metadata only. They never contain chat
plaintext, private keys, recovery secrets, or real user data.
