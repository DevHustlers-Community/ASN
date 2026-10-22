# ASN - Arabian Social Network

An open-source social platform for conversations, communities, and real-time
communication.

> Status: architecture and incremental service scaffolding. The Chat and Event
> broker apps compile and run locally against PostgreSQL 18; no product APIs,
> API/event contracts, or migrations exist yet. The current design is
> documented in
> [`docs/architecture/architecture-and-schema.md`](docs/architecture/architecture-and-schema.md).

## Stack

| Layer | Technology |
|---|---|
| Social API | Bun + TypeScript |
| Chat service | Elixir + Phoenix + Ecto |
| Moderation API | Bun + TypeScript |
| Event broker | Elixir/OTP + Ecto, PostgreSQL-backed (custom, no external broker) |
| Web and admin | React + TypeScript |
| Mobile | React Native + TypeScript |
| Database | PostgreSQL 18+ (local baseline 18.6), one database per service |
| Media | S3-compatible object storage (R2) |

## Repository map

| Path | Contents |
|---|---|
| [`apps/`](apps/README.md) | Web, mobile, and admin clients |
| [`services/`](services/README.md) | Social API, Chat, Moderation, Event broker |
| [`contracts/`](contracts/README.md) | OpenAPI and versioned event schemas |
| [`packages/`](packages/README.md) | Shared TypeScript tooling and generated clients |
| [`infrastructure/`](infrastructure/README.md) | Compose, proxy, databases, operations |
| [`tests/`](tests/README.md) | Cross-service integration, contract, and end-to-end tests |
| [`scripts/`](scripts/README.md) | Development and CI helpers |
| [`docs/`](docs/README.md) | Architecture, decisions, security, development, operations |
| [`.github/`](.github/README.md) | CI workflows and repository templates |

## Principles

- One service owns one database. No cross-database reads, foreign keys, or
  transactions.
- REST for request/response. A custom Elixir broker for asynchronous events.
  WebSockets only for live chat delivery.
- Transactional outbox + idempotent consumers. Delivery is at-least-once.
- Chat is E2EE by design: servers store opaque envelopes, never plaintext body
  content or private keys.
- Contracts first: OpenAPI and versioned event schemas are validated in CI.
- No global business service and no global single-writer bottleneck.

## Getting started

See [`docs/development/getting-started.md`](docs/development/getting-started.md)
for prerequisites, the local PostgreSQL stack, and the Chat and broker run
commands. Environment variables are named in [`.env.example`](.env.example);
never commit real credentials.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Significant decisions require an ADR in
[`docs/decisions/`](docs/decisions/README.md). Every content commit needs a change
record in [`docs/changelog/`](docs/changelog/README.md).

## For AI agents

Read [`AGENTS.md`](AGENTS.md) before changing code, contracts, or documentation.
It defines the source-of-truth order, ownership boundaries, security rules, and
verification expectations for automated contributors. Domain terms and field
meanings are defined in [`docs/GLOSSARY.md`](docs/GLOSSARY.md).

## Security

See [`SECURITY.md`](SECURITY.md). Report vulnerabilities privately, never in a
public issue.

## License

Licensed under the GNU Affero General Public License v3.0. See
[`LICENSE`](LICENSE).
