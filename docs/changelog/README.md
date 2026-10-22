# Change records

Every commit that changes repository content must include a **change record**: a
short Markdown file in this folder describing what changed, why, and how it was
verified. Records are the source for release notes and for review context.

This folder is not a copy of the architecture document. It records changes over
time; the architecture document always describes the current design only.

## One record per commit

- Add or update exactly one record per commit, in the same commit as the change.
- Keep commits focused. If a commit contains unrelated work, split it and give
  each commit its own record.
- The record is public. Never include secrets, tokens, private keys, plaintext
  chat content, real user data, exploit details, or evidence payloads.
- Do not delete merged records. Correct them with a follow-up record.

**Exceptions:**

- Merge commits do not need a record.
- Squash commits created by the hosting platform are exempt from the trailer;
  the pull request commits were already validated before merge.
- A commit that only edits files in this folder is exempt from both the new
  record and the `Changelog:` trailer.
- Security work under embargo gets a public record with a non-sensitive summary
  when disclosure is safe. Follow [`SECURITY.md`](../../SECURITY.md).

## Filename

`YYYY-MM-DD-short-slug.md`

- `YYYY-MM-DD` is the UTC date of the commit.
- `short-slug` is lowercase kebab-case, 2-8 words, describing the change.
- Example: `2026-10-22-governance-and-changelog.md`.

Files sort chronologically by name. Do not reuse or rename a merged record.

## Format

Use [`TEMPLATE.md`](TEMPLATE.md). Required front matter:

| Key | Required | Value |
|---|---|---|
| `date` | yes | `YYYY-MM-DD`; must match the filename |
| `type` | yes | `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `build`, `perf`, `security`, `revert` |
| `scope` | no | Short area, for example `chat`, `contracts`, `governance` |
| `summary` | yes | One line, at most 120 characters |
| `breaking` | yes | `true` or `false` |
| `adr` | no | ADR ID(s), or `-` |
| `contracts` | no | Contract paths changed, or `-` |

The body must include `## Change`, `## Why`, and `## Verification`. Add
`## Follow-ups` when something remains open.

## Enforce it locally

Enable the repository hooks once per clone:

```bash
bash scripts/dev/install-git-hooks.sh
```

Then:

- `.githooks/pre-commit` rejects a content commit with no staged record.
- `.githooks/commit-msg` requires a trailer in the commit message:

```text
Changelog: docs/changelog/2026-10-22-governance-and-changelog.md
```

CI runs `scripts/ci/check-changelog.py` on every pull request commit and rejects
a commit without a record, with invalid front matter, or without a `Changelog:`
trailer that names a file changed in that commit. Pushes to `main` validate every
record and all relative links; they do not re-check trailers on platform-created
squash commits.

## Change record, CHANGELOG.md, and ADR

| Artifact | Answers | Lifetime |
|---|---|---|
| Change record (this folder) | What changed in this commit, and why? | One per commit, permanent |
| [`CHANGELOG.md`](../../CHANGELOG.md) | What changed in this release? | Aggregated at release time |
| [ADR](../decisions/README.md) | Why was a hard-to-reverse decision made? | Permanent, superseded by newer ADRs |

At release time, the maintainer groups records into `CHANGELOG.md`. Do not
duplicate every record into the release changelog by hand before a release.
