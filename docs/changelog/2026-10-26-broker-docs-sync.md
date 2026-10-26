---
date: 2026-10-26
type: docs
scope: services
summary: Sync event broker documentation with the completed v1 surface
breaking: false
adr: "0008"
contracts: openapi/event-broker-api.yaml
---

# Sync event broker documentation with the completed v1 surface

## Change

- `services/event-broker/README.md` status now reflects the implemented v1
  surface (HTTP edge with scoped bearer credentials, dead-letter replay/skip
  with the audit trail, retention, telemetry, and the chat-side relay as the
  first producer) and the local-development section documents the HTTP
  listener port and the `BROKER_ADMIN_TOKEN` first-boot bootstrap.
- `services/event-broker/CODE_MAP.md` transport boundary records the adapter
  as implemented at `web/router.ex` under the landed
  `contracts/openapi/event-broker-api.yaml` contract, keeping the
  no-routing-rules-at-the-edge rule visible.

## Why

The broker's v1 implementation completed across this session; the service
docs must not describe implemented behavior as missing.

## Verification

- `python3 scripts/ci/check-links.py` and
  `python3 scripts/ci/check-changelog.py --all` — run; pass.
- Documentation-only change; service suites were not affected (63/63 in the
  same session).

## Follow-ups

- Metrics exposition, credential-management endpoints, and the cross-service
  e2e harness remain the next surfaces.
