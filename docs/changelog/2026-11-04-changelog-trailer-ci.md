---
date: 2026-11-04
type: chore
scope: ci
summary: Enforce the Changelog trailer on pull request commits
breaking: false
adr: -
contracts: -
---

# Enforce the Changelog trailer on pull request commits

## Change

- `scripts/ci/check-commit-trailer.py` gained a range mode:

  ```bash
  python3 scripts/ci/check-commit-trailer.py --range origin/main..HEAD
  ```

  It walks `git rev-list --no-merges <range>`, reads each message with
  `git log -1 --format=%B`, skips merge, `fixup!`, `squash!`, and `amend!`
  subjects, skips commits that only touch `docs/changelog/`, requires exactly one
  `Changelog: docs/changelog/YYYY-MM-DD-slug.md` trailer, and checks the record
  exists in that commit's tree (`git cat-file -e <sha>:<path>`), not in the
  index. The message-file mode used by `.githooks/commit-msg` is unchanged and
  remains the default.
- [`.github/workflows/governance.yml`](../../.github/workflows/governance.yml):
  new `Validate Changelog trailers in pull request commits` step, guarded by
  `if: github.event_name == 'pull_request'`, after
  `git fetch --no-tags origin "$BASE_REF"` and before the all-records check. It
  uses the existing `fetch-depth: 0` checkout.
- [`docs/changelog/README.md`](README.md): documents the range gate and how it
  differs from `check-changelog.py`.
- [`scripts/README.md`](../../scripts/README.md): lists both modes of the
  trailer script.

## Why

Issue #26. `.githooks/commit-msg` is opt-in (`scripts/dev/install-git-hooks.sh`),
so the trailer gate only ran for contributors who installed the hooks. The
script also assumed the hook context: it read `git diff --cached` and checked
`git cat-file -e :<path>`, which cannot work in CI because the index does not
contain the pull request commits.

`check-changelog.py --range` already rejected a missing trailer (its record
validation requires exactly one), so the reported gap was partly closed before
this change. This change makes the script that owns the trailer policy run in
CI, gives a focused failure message, and closes the remaining gap: a commit with
an empty diff skipped `validate_commit` in `check-changelog.py`, because its
checks are guarded by `if files`; the trailer script rejects that commit.

## Verification

- Local range-mode acceptance tests in a scratch Git repository:
  - non-merge commit with a record and trailer → `0`;
  - non-merge commit without a trailer → `1`;
  - merge commit → skipped, `0`;
  - commit that only edits `docs/changelog/` → `0`;
  - trailer naming a record absent from the commit → `1`;
  - malformed range (`--range nope`) → `2`.
- `python3 scripts/ci/check-commit-trailer.py --range origin/main..HEAD` on this
  branch → `0`.
- Existing open pull requests still pass: the same range check over
  `origin/main..origin/ci/25-e2e-workflow` (16 non-merge commits, including a
  merge from `main`) → `0`.
- `python3 scripts/ci/check-changelog.py --all` and `python3
  scripts/ci/check-links.py` → pass.
- CI, pull request #37: `Change records and links` green in 5 s; the new
  `Validate Changelog trailers in pull request commits` step ran and passed.
- Negative test, scratch pull request #38: one empty non-merge commit with no
  trailer. `Validate change records in pull request commits` passed because the
  commit has no diff, the new step failed with `commit message needs a trailer:
  Changelog: docs/changelog/YYYY-MM-DD-short-slug.md`, and the later steps were
  skipped. This is the empty-commit gap described under Why. The scratch pull
  request and branch were deleted after the run.

## Follow-ups

- Contract validation and client-generation checks remain separate governance
  work, tracked by their own issues.
