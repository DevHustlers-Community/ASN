# Scripts

Developer and CI helpers. Each script must be safe to run locally and must fail
loudly.

| Path | Purpose |
|---|---|
| `dev/install-git-hooks.sh` | Point Git at `.githooks/` for local change-record enforcement |
| `dev/broker-verify.sh` | Full event-broker verification loop: compose PostgreSQL, wait for health, migrate, format, compile, test |
| `dev/broker-load.py` | Event-broker benchmark harness (B1-B9): plan checks, publish/claim load, backlog drain, retention, metrics, authorize. Stdlib only; local DB by default |
| `ci/check-changelog.py` | Validate change-record names, front matter, and per-commit presence |
| `ci/check-commit-trailer.py` | Require a `Changelog:` trailer in commit messages |
| `ci/check-links.py` | Verify relative links in Markdown files |
| `db/` | Explicit migration, reset, and backup/restore helpers per service (planned) |
| `contracts/` | Validate schemas and regenerate clients/types (planned) |

**Rules:**

- No script reads secrets from source. Use environment variables and
  `.env.example` placeholders.
- Migration helpers never run across service databases in one transaction.
- Destructive database commands require an explicit flag and a named target
  environment.
- Backup scripts operate on snapshots, never on live SQLite/WAL file sets.

**Status:** governance scripts, the hook installer, and the broker verify
loop exist. Migration and contract scripts land with the next runnable
services and the contracts tooling.
