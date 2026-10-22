#!/usr/bin/env sh
set -eu

root=$(git rev-parse --show-toplevel)

if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' "python3 is required for the change-record hooks." >&2
  exit 1
fi

chmod +x "$root/.githooks/pre-commit" "$root/.githooks/commit-msg"
git -C "$root" config core.hooksPath .githooks

printf '%s\n' "Installed ASN hooks from .githooks." \
  "Every content commit now needs a staged docs/changelog record and a Changelog: trailer."
