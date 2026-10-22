#!/usr/bin/env python3
"""Check that relative links in Markdown files resolve."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]
SKIP_DIRS = {
    ".git",
    "node_modules",
    "_build",
    "deps",
    ".elixir_ls",
    "dist",
    "build",
    ".next",
    "target",
}
LINK_RE = re.compile(r"\]\(([^)]+)\)")


def strip_code(text: str) -> str:
    lines: list[str] = []
    fenced = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fenced = not fenced
            lines.append("")
            continue
        lines.append("" if fenced else line)
    without_fences = "\n".join(lines)
    return re.sub(r"`[^`\n]*`", "", without_fences)


def iter_markdown() -> list[Path]:
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name.endswith(".md"):
                files.append(Path(dirpath) / name)
    return files


def main() -> int:
    errors: list[str] = []
    for path in iter_markdown():
        text = strip_code(path.read_text(encoding="utf-8"))
        for match in LINK_RE.finditer(text):
            link = match.group(1).strip()
            if not link or link.startswith(("#", "http://", "https://", "mailto:", "tel:")):
                continue
            if link.startswith("<") and ">" in link:
                link = link[1 : link.index(">")]
            else:
                link = link.split()[0]
            link = unquote(link.split("#", 1)[0].split("?", 1)[0])
            if not link:
                continue
            target = (path.parent / link).resolve()
            if not target.exists():
                rel = path.relative_to(ROOT)
                errors.append(f"{rel}: broken relative link '{link}'")

    if errors:
        for error in errors:
            print(f"ERROR {error}", file=sys.stderr)
        return 1

    print("Relative documentation links OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
