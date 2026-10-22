#!/usr/bin/env python3
"""Require a Changelog trailer in every non-merge commit message."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TRAILER_RE = re.compile(
    r"^Changelog:\s*(docs/changelog/\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*\.md)\s*$",
    re.MULTILINE,
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-commit-trailer.py <commit-msg-file>", file=sys.stderr)
        return 2

    message = Path(sys.argv[1]).read_text(encoding="utf-8").replace("\r\n", "\n")
    subject = message.splitlines()[0] if message.splitlines() else ""

    if subject.startswith(("Merge ", "fixup! ", "squash! ", "amend! ")):
        return 0

    staged = subprocess.run(
        ["git", "diff", "--cached", "--name-only"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    if staged and all(path.startswith("docs/changelog/") for path in staged):
        return 0

    matches = TRAILER_RE.findall(message)
    if not matches:
        print(
            "ERROR commit message needs a trailer:\n"
            "  Changelog: docs/changelog/YYYY-MM-DD-short-slug.md",
            file=sys.stderr,
        )
        return 1

    if len(matches) > 1:
        print("ERROR commit message has more than one Changelog trailer", file=sys.stderr)
        return 1

    rel = matches[0]
    result = subprocess.run(
        ["git", "cat-file", "-e", f":{rel}"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(
            f"ERROR {rel} is not staged in this commit; stage the change record too",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
