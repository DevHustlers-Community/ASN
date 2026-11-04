#!/usr/bin/env python3
"""Fail when dependency audits report advisories.

`bun audit` and `mix hex.audit` do not have a reliable exit status across
versions: `mix hex.audit` exits 0 while printing advisories, and older Bun
releases did the same. Parse their output and fail closed on unknown output
instead of trusting the exit code.

Usage:
    python3 scripts/ci/check-audits.py bun
    python3 scripts/ci/check-audits.py hex services/event-broker
    python3 scripts/ci/check-audits.py all
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HEX_SERVICES = ("services/event-broker", "services/chat-service")
HEX_ADVISORY_MARKERS = (
    "Found packages with security advisories",
    "Advisories:",
)


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return None


def check_bun() -> list[str]:
    result = run(["bun", "audit", "--json"], ROOT)
    if result is None:
        return ["bun is not installed"]

    raw = result.stdout.strip()
    try:
        advisories = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        if raw:
            print(raw, file=sys.stderr)
        if result.stderr.strip():
            print(result.stderr.strip(), file=sys.stderr)
        return ["bun audit did not return valid JSON"]

    if not isinstance(advisories, dict):
        return ["bun audit returned an unexpected JSON shape"]

    errors: list[str] = []
    for package, entries in sorted(advisories.items()):
        if not isinstance(entries, list) or not entries:
            errors.append(f"bun audit: unexpected entry for {package}")
            continue

        for advisory in entries:
            if not isinstance(advisory, dict):
                errors.append(f"bun audit: unexpected advisory for {package}")
                continue

            severity = advisory.get("severity", "unknown")
            title = advisory.get("title", "untitled advisory")
            url = advisory.get("url")
            line = f"{package}: {severity}: {title}"
            if url:
                line = f"{line} ({url})"
            errors.append(line)

    if advisories:
        return errors

    if result.returncode != 0:
        if result.stderr.strip():
            print(result.stderr.strip(), file=sys.stderr)
        return [f"bun audit failed with exit code {result.returncode}"]

    print("bun audit: no advisories")
    return []


def check_hex(service: str) -> list[str]:
    service_dir = ROOT / service
    if not service_dir.is_dir():
        return [f"mix hex.audit: {service} is not a directory"]

    result = run(["mix", "hex.audit"], service_dir)
    if result is None:
        return ["mix is not installed"]

    output = (result.stdout + result.stderr).strip()
    clean = "No retired or security advisory packages found" in output

    if clean and result.returncode == 0:
        print(f"mix hex.audit ({service}): no advisories")
        return []

    if output:
        print(output, file=sys.stderr)

    if any(marker in output for marker in HEX_ADVISORY_MARKERS):
        return [f"mix hex.audit ({service}): advisories found"]

    return [f"mix hex.audit ({service}): failed with exit code {result.returncode}"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "ecosystem",
        choices=("bun", "hex", "all"),
        help="which audit to run",
    )
    parser.add_argument(
        "services",
        nargs="*",
        help="Hex service directories (default: every Elixir service)",
    )
    args = parser.parse_args()

    if args.ecosystem == "bun" and args.services:
        parser.error("the bun audit does not take service directories")

    errors: list[str] = []
    if args.ecosystem in ("bun", "all"):
        errors.extend(check_bun())
    if args.ecosystem in ("hex", "all"):
        for service in args.services or HEX_SERVICES:
            errors.extend(check_hex(service))

    if errors:
        print("Dependency audit failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1

    print("Dependency audits OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
