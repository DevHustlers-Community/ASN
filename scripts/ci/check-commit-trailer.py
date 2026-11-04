#!/usr/bin/env python3
"""Require a Changelog trailer in every non-merge commit message.

Modes:
  <commit-msg-file>  validate one message being committed (the commit-msg hook
                     reads the index, so the record must be staged)
  --range A..B       validate every non-merge commit in the range (CI: the index
                     is empty, so the record must exist in the commit itself)

Both modes skip merge commits and commits that only edit `docs/changelog/`.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECORD_DIR = "docs/changelog/"
TRAILER_RE = re.compile(
    r"^Changelog:\s*(docs/changelog/\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*\.md)\s*$",
    re.MULTILINE,
)
SKIP_SUBJECTS = ("Merge ", "fixup! ", "squash! ", "amend! ")


class ValidationError(Exception):
    pass


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        raise ValidationError(
            f"git {' '.join(args)} failed: {result.stderr.strip() or result.stdout.strip()}"
        )
    return result.stdout


def git_ok(*args: str) -> bool:
    return (
        subprocess.run(
            ["git", *args],
            cwd=ROOT,
            text=True,
            capture_output=True,
        ).returncode
        == 0
    )


def trailers(message: str) -> list[str]:
    return TRAILER_RE.findall(message)


def skip_subject(message: str) -> bool:
    subject = message.splitlines()[0] if message.splitlines() else ""
    return subject.startswith(SKIP_SUBJECTS)


def check_record(rel: str, exists) -> str | None:
    if not exists(rel):
        return f"{rel} is not present in this commit"
    return None


def check_message(message: str, exists) -> list[str]:
    found = trailers(message)
    if not found:
        return [
            "commit message needs a trailer: "
            "Changelog: docs/changelog/YYYY-MM-DD-short-slug.md"
        ]
    if len(found) > 1:
        return ["commit message has more than one Changelog trailer"]

    problem = check_record(found[0], exists)
    return [problem] if problem else []


def check_file(path: str) -> int:
    message = Path(path).read_text(encoding="utf-8").replace("\r\n", "\n")
    if skip_subject(message):
        return 0

    staged = git("diff", "--cached", "--name-only").splitlines()
    if staged and all(name.startswith(RECORD_DIR) for name in staged):
        return 0

    problems = check_message(message, lambda rel: git_ok("cat-file", "-e", f":{rel}"))
    for problem in problems:
        if problem.startswith("commit message has"):
            print(f"ERROR {problem}", file=sys.stderr)
        elif problem.startswith(RECORD_DIR):
            print(
                f"ERROR {problem}; stage the change record too",
                file=sys.stderr,
            )
        else:
            print(f"ERROR {problem}", file=sys.stderr)
    return 1 if problems else 0


def check_range(spec: str) -> int:
    if ".." not in spec:
        print(f"ERROR --range needs BASE..HEAD, got {spec!r}", file=sys.stderr)
        return 2

    try:
        commits = git("rev-list", "--no-merges", spec).split()
    except ValidationError as error:
        print(f"ERROR {error}", file=sys.stderr)
        return 2

    failures = 0
    for sha in commits:
        message = git("log", "-1", "--format=%B", sha)
        if skip_subject(message):
            continue

        changed = [
            name
            for name in git("show", "--name-only", "--format=", sha).splitlines()
            if name
        ]
        if changed and all(name.startswith(RECORD_DIR) for name in changed):
            continue

        subject = message.splitlines()[0] if message.splitlines() else ""
        problems = check_message(
            message, lambda rel, sha=sha: git_ok("cat-file", "-e", f"{sha}:{rel}")
        )
        for problem in problems:
            print(f"ERROR {sha[:12]} {subject}\n  {problem}", file=sys.stderr)
            failures += 1

    if failures:
        print(
            f"ERROR {failures} problem(s) in {len(commits)} commit(s) in {spec}",
            file=sys.stderr,
        )
        return 1

    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "--range":
        return check_range(argv[1])

    if len(argv) == 1 and not argv[0].startswith("-"):
        return check_file(argv[0])

    print(
        "usage: check-commit-trailer.py <commit-msg-file>\n"
        "       check-commit-trailer.py --range BASE..HEAD",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
