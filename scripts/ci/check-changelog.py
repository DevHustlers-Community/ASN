#!/usr/bin/env python3
"""Validate ASN change records under docs/changelog/.

Modes:
  --all              validate every current record (default)
  --staged           require and validate a staged record; used by pre-commit
  --range A..B       require a record in every non-merge commit in the range
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECORD_DIR = "docs/changelog/"
NAME_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-([a-z0-9]+(?:-[a-z0-9]+)*)\.md$")
SKIP_NAMES = {"readme.md", "template.md", "_template.md"}
TYPES = {
    "feat",
    "fix",
    "docs",
    "refactor",
    "test",
    "chore",
    "ci",
    "build",
    "perf",
    "security",
    "revert",
}
REQUIRED_KEYS = ("date", "type", "summary", "breaking")
MAX_SUMMARY = 120
EXAMPLE = "docs/changelog/YYYY-MM-DD-short-slug.md"
TRAILER_RE = re.compile(
    r"^Changelog:\s*(docs/changelog/\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*\.md)\s*$",
    re.MULTILINE,
)


class ValidationError(Exception):
    pass


def run_git(*args: str) -> str:
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


def is_record(path: str) -> bool:
    if not path.startswith(RECORD_DIR) or not path.endswith(".md"):
        return False
    return Path(path).name.lower() not in SKIP_NAMES


def parse_front_matter(text: str) -> tuple[dict[str, str], str]:
    text = text.replace("\r\n", "\n")
    if not text.startswith("---\n"):
        raise ValidationError("missing YAML front matter starting with '---'")
    end = text.find("\n---\n", 4)
    if end == -1:
        raise ValidationError("front matter is not closed with '---'")
    block = text[4:end]
    body = text[end + 5 :]

    data: dict[str, str] = {}
    for lineno, line in enumerate(block.split("\n"), start=2):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            raise ValidationError(f"front matter line {lineno} is not 'key: value'")
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            raise ValidationError(f"front matter line {lineno} has an empty key")
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        data[key] = value

    return data, body


def validate_record(path: Path, text: str) -> list[str]:
    errors: list[str] = []
    rel = path.as_posix()

    match = NAME_RE.match(path.name)
    if not match:
        errors.append(
            f"{rel}: filename must be YYYY-MM-DD-slug.md using lowercase kebab-case"
        )
        filename_date = None
    else:
        filename_date = match.group(1)

    try:
        data, body = parse_front_matter(text)
    except ValidationError as exc:
        return [f"{rel}: {exc}"]

    for key in REQUIRED_KEYS:
        if not data.get(key):
            errors.append(f"{rel}: missing required front matter key '{key}'")

    record_date = data.get("date", "")
    if record_date:
        try:
            date.fromisoformat(record_date)
        except ValueError:
            errors.append(f"{rel}: date '{record_date}' is not YYYY-MM-DD")
        else:
            if len(record_date) != 10:
                errors.append(f"{rel}: date must be exactly YYYY-MM-DD")
            if filename_date and record_date != filename_date:
                errors.append(
                    f"{rel}: date '{record_date}' does not match filename date '{filename_date}'"
                )

    record_type = data.get("type", "")
    if record_type and record_type not in TYPES:
        errors.append(
            f"{rel}: type '{record_type}' is not one of {', '.join(sorted(TYPES))}"
        )

    breaking = data.get("breaking", "").lower()
    if breaking and breaking not in {"true", "false"}:
        errors.append(f"{rel}: breaking must be 'true' or 'false'")

    summary = data.get("summary", "")
    if summary:
        if "\n" in summary:
            errors.append(f"{rel}: summary must be a single line")
        if len(summary) > MAX_SUMMARY:
            errors.append(f"{rel}: summary is longer than {MAX_SUMMARY} characters")

    if not body.strip():
        errors.append(f"{rel}: body is empty; describe the change")
    else:
        for heading in ("## Change", "## Why", "## Verification"):
            if heading not in body:
                errors.append(f"{rel}: body is missing '{heading}'")

    return errors


def validate_all() -> list[str]:
    errors: list[str] = []
    if not (ROOT / RECORD_DIR).is_dir():
        return [f"{RECORD_DIR}: directory does not exist"]

    records = sorted(
        p for p in (ROOT / RECORD_DIR).glob("*.md") if p.name.lower() not in SKIP_NAMES
    )
    for path in records:
        errors.extend(validate_record(path.relative_to(ROOT), path.read_text(encoding="utf-8")))

    return errors


def validate_staged() -> list[str]:
    errors: list[str] = []
    staged = [p for p in run_git("diff", "--cached", "--name-only", "--diff-filter=ACMR").splitlines() if p]
    records = [p for p in staged if is_record(p)]
    other = [p for p in staged if not p.startswith(RECORD_DIR)]

    if other and not records:
        errors.append(
            "staged changes need a change record: add or update a file under "
            f"{RECORD_DIR} named like {EXAMPLE}"
        )

    for rel in records:
        try:
            text = run_git("show", f":{rel}")
        except ValidationError as exc:
            errors.append(f"{rel}: cannot read staged content ({exc})")
            continue
        errors.extend(validate_record(Path(rel), text))

    return errors


def validate_commit(sha: str, files: list[str]) -> list[str]:
    message = run_git("log", "-1", "--format=%B", sha)
    subject = message.splitlines()[0] if message.splitlines() else ""
    if subject.startswith(("fixup! ", "squash! ", "amend! ")):
        return []

    errors: list[str] = []
    matches = TRAILER_RE.findall(message)
    if len(matches) != 1:
        errors.append(
            f"{sha[:12]} {subject}: commit message needs exactly one "
            "'Changelog: docs/changelog/<record>.md' trailer"
        )
    elif matches[0] not in files:
        errors.append(
            f"{sha[:12]} {subject}: trailer names {matches[0]}, "
            "which this commit does not change"
        )
    return errors

def validate_range(rev_range: str) -> list[str]:
    errors: list[str] = []
    try:
        commits = run_git("rev-list", "--no-merges", "--reverse", rev_range).splitlines()
    except ValidationError as exc:
        return [f"cannot resolve range '{rev_range}': {exc}"]

    if not commits:
        return []

    for sha in commits:
        try:
            files = run_git(
                "diff-tree", "--no-commit-id", "--name-only", "-r", "--root", sha
            ).splitlines()
        except ValidationError as exc:
            errors.append(f"{sha[:12]}: cannot inspect commit ({exc})")
            continue

        changelog_only = bool(files) and all(
            path.startswith(RECORD_DIR) for path in files
        )
        if files and not changelog_only and not any(is_record(path) for path in files):
            subject = run_git("log", "-1", "--format=%s", sha).strip()
            errors.append(
                f"{sha[:12]} {subject}: commit has no change record under {RECORD_DIR}"
            )

        if files and not changelog_only:
            errors.extend(validate_commit(sha, files))

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="validate all current records")
    parser.add_argument("--staged", action="store_true", help="validate staged changes")
    parser.add_argument("--range", dest="rev_range", help="require a record per commit in A..B")
    args = parser.parse_args()

    if sum(bool(x) for x in (args.all, args.staged, args.rev_range)) > 1:
        parser.error("choose only one of --all, --staged, or --range")

    os.chdir(ROOT)
    errors: list[str] = []

    if args.staged:
        errors.extend(validate_staged())
    elif args.rev_range:
        errors.extend(validate_range(args.rev_range))
        errors.extend(validate_all())
    else:
        errors.extend(validate_all())

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1

    print("Change records OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
