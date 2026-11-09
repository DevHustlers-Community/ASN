#!/usr/bin/env python3
"""Validate the ASN REST and event contracts.

Checks:

- every OpenAPI document under ``contracts/openapi/`` is valid OpenAPI 3.1;
- no YAML contract repeats a mapping key (YAML would silently keep the last one);
- every external ``$ref`` resolves to an existing file and JSON Pointer;
- the broker ``EventEnvelope`` component matches the shared envelope schema;
- every ``*.schema.json`` under ``contracts/events/`` is a valid JSON Schema;
- every payload schema is named ``<event-type>.v<version>.schema.json`` and its
  ``$id`` matches its path;
- every ``contracts/events/examples/valid-*.json`` satisfies the envelope and,
  when one exists, the payload schema named by its ``type`` and
  ``schema_version``;
- every ``contracts/events/examples/invalid-*.json`` is rejected by it;
- on a pull request, a removed path, operation, or required field without an
  ``info.version`` bump fails the check.

Usage:

    python3 scripts/contracts/validate.py
    python3 scripts/contracts/validate.py --base-ref origin/main
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

import yaml
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate as validate_openapi_spec

ROOT = Path(__file__).resolve().parents[2]
OPENAPI_DIR = ROOT / "contracts" / "openapi"
EVENTS_DIR = ROOT / "contracts" / "events"
EXAMPLES_DIR = EVENTS_DIR / "examples"
ENVELOPE_SCHEMA = EVENTS_DIR / "common" / "event-envelope.schema.json"
HTTP_METHODS = {"get", "put", "post", "delete", "options", "head", "patch", "trace"}
PAYLOAD_SCHEMA_NAME = re.compile(
    r"^(?P<type>.+)\.v(?P<version>\d+)\.schema\.json$"
)


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


class DuplicateKeyError(ValueError):
    """Raised when a YAML mapping repeats a key."""


class StrictLoader(yaml.SafeLoader):
    """Safe loader that rejects duplicate mapping keys.

    YAML keeps the last duplicate key silently, so a repeated response status
    hides the earlier one and the rendered documentation shows the wrong text.
    """


def _construct_mapping(
    loader: StrictLoader, node: yaml.MappingNode, deep: bool = False
):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            line = key_node.start_mark.line + 1
            raise DuplicateKeyError(f"duplicate key {key!r} at line {line}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


StrictLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping
)


def load_yaml(path: Path):
    with path.open(encoding="utf-8") as handle:
        return yaml.load(handle, Loader=StrictLoader)


def load_contract(path: Path):
    suffix = path.suffix.lower()
    if suffix == ".json":
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    if suffix in (".yaml", ".yml"):
        return load_yaml(path)
    raise ValueError(f"unsupported contract file type: {path.suffix}")


def openapi_paths() -> list[Path]:
    return sorted([*OPENAPI_DIR.glob("*.yaml"), *OPENAPI_DIR.glob("*.yml")])


def iter_refs(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "$ref" and isinstance(value, str):
                yield value
            else:
                yield from iter_refs(value)
    elif isinstance(node, list):
        for value in node:
            yield from iter_refs(value)


def resolve_json_pointer(document, fragment: str):
    if not fragment:
        return document
    if not fragment.startswith("/"):
        raise ValueError(f"unsupported fragment #{fragment}")

    current = document
    for raw in fragment[1:].split("/"):
        token = unquote(raw).replace("~1", "/").replace("~0", "~")
        if isinstance(current, list):
            current = current[int(token)]
        elif isinstance(current, dict):
            current = current[token]
        else:
            raise KeyError(token)
    return current


def check_refs(path: Path, document) -> list[str]:
    errors: list[str] = []
    label = relative(path)

    for ref in iter_refs(document):
        target_name, _, fragment = ref.partition("#")
        if target_name:
            target = (path.parent / unquote(target_name)).resolve()
            if not target.is_file():
                errors.append(f"{label}: $ref target does not exist: {ref}")
                continue
            try:
                target_document = load_contract(target)
            except Exception as exc:  # noqa: BLE001 - report the load failure
                errors.append(f"{label}: $ref target cannot be read ({ref}): {exc}")
                continue
        else:
            target_document = document

        try:
            resolve_json_pointer(target_document, fragment)
        except Exception as exc:  # noqa: BLE001 - report the resolution failure
            errors.append(f"{label}: $ref cannot be resolved ({ref}): {exc}")

    return errors


def check_envelope_alignment(label: str, spec, envelope) -> list[str]:
    component = (
        spec.get("components", {})
        .get("schemas", {})
        .get("EventEnvelope")
    )
    if component is None:
        return []

    errors: list[str] = []
    shared_required = set(envelope.get("required", []))
    openapi_required = set(component.get("required", []))
    if shared_required != openapi_required:
        errors.append(
            f"{label}: EventEnvelope required fields differ from "
            f"{relative(ENVELOPE_SCHEMA)}: "
            f"shared={sorted(shared_required)} openapi={sorted(openapi_required)}"
        )

    shared_properties = set(envelope.get("properties", {}))
    openapi_properties = set(component.get("properties", {}))
    if shared_properties != openapi_properties:
        errors.append(
            f"{label}: EventEnvelope properties differ from "
            f"{relative(ENVELOPE_SCHEMA)}: "
            f"shared={sorted(shared_properties)} openapi={sorted(openapi_properties)}"
        )

    return errors


def validate_openapi(envelope) -> list[str]:
    errors: list[str] = []
    paths = openapi_paths()
    if not paths:
        return [f"no OpenAPI files under {relative(OPENAPI_DIR)}"]

    for path in paths:
        label = relative(path)
        try:
            spec = load_yaml(path)
            validate_openapi_spec(spec)
        except Exception as exc:  # noqa: BLE001 - report the validator's message
            errors.append(f"{label}: {type(exc).__name__}: {exc}")
            continue

        file_errors = check_refs(path, spec)
        file_errors.extend(check_envelope_alignment(label, spec, envelope))
        errors.extend(file_errors)
        if not file_errors:
            version = (spec.get("info") or {}).get("version")
            print(f"OpenAPI OK: {label} ({spec.get('openapi')}, version {version})")

    return errors


def payload_schema_index(
    schema_paths: list[Path], schemas: dict[Path, dict]
) -> tuple[dict[tuple[str, int], Path], set[str], list[str]]:
    """Map ``(event_type, schema_version)`` to the payload schema file."""
    index: dict[tuple[str, int], Path] = {}
    namespaces: set[str] = set()
    errors: list[str] = []

    for path in schema_paths:
        if path == ENVELOPE_SCHEMA or path not in schemas:
            continue

        label = relative(path)
        match = PAYLOAD_SCHEMA_NAME.match(path.name)
        if match is None:
            errors.append(
                f"{label}: payload schema name must be "
                f"<event-type>.v<version>.schema.json"
            )
            continue

        event_type = match.group("type")
        version = int(match.group("version"))
        key = (event_type, version)
        if key in index:
            errors.append(
                f"{label}: duplicate payload schema for {event_type} "
                f"version {version} (also {relative(index[key])})"
            )
            continue

        index[key] = path
        if path.parent != EVENTS_DIR:
            namespaces.add(path.parent.name)

    return index, namespaces, errors


def check_payload_binding(
    label: str,
    instance: dict,
    index: dict[tuple[str, int], Path],
    namespaces: set[str],
    validators: dict[tuple[str, int], Draft202012Validator],
) -> list[str]:
    """Validate an example's payload against the schema for its type."""
    event_type = instance.get("type")
    schema_version = instance.get("schema_version")
    if not isinstance(event_type, str) or not isinstance(schema_version, int):
        return []

    key = (event_type, schema_version)
    schema_path = index.get(key)
    if schema_path is None:
        namespace = event_type.split(".", 1)[0]
        if namespace in namespaces:
            return [
                f"{label}: no payload schema for {event_type} "
                f"version {schema_version}"
            ]
        return []

    payload_errors = validators[key].iter_errors(instance.get("payload"))
    return [
        f"{label}: payload does not match {relative(schema_path)}: {error.message}"
        for error in sorted(payload_errors, key=lambda e: e.message)
    ]


def validate_events(envelope) -> list[str]:
    errors: list[str] = []
    schema_paths = sorted(EVENTS_DIR.rglob("*.schema.json"))
    schemas: dict[Path, dict] = {}

    for path in schema_paths:
        label = relative(path)
        try:
            with path.open(encoding="utf-8") as handle:
                schema = json.load(handle)
            Draft202012Validator.check_schema(schema)
        except Exception as exc:  # noqa: BLE001 - report the schema failure
            errors.append(f"{label}: invalid JSON Schema: {type(exc).__name__}: {exc}")
            continue

        expected_id = path.relative_to(EVENTS_DIR).as_posix()
        if schema.get("$id") != expected_id:
            errors.append(
                f"{label}: $id must be {expected_id!r} to bind the schema "
                f"to its event type"
            )

        schemas[path] = schema
        errors.extend(check_refs(path, schema))

    index, namespaces, index_errors = payload_schema_index(schema_paths, schemas)
    errors.extend(index_errors)

    validators = {
        key: Draft202012Validator(schemas[path], format_checker=FormatChecker())
        for key, path in index.items()
    }

    validator = Draft202012Validator(envelope, format_checker=FormatChecker())
    examples = sorted(EXAMPLES_DIR.glob("*.json"))
    valid = 0
    invalid = 0

    for path in examples:
        label = relative(path)
        try:
            with path.open(encoding="utf-8") as handle:
                instance = json.load(handle)
        except Exception as exc:  # noqa: BLE001 - report the JSON failure
            errors.append(f"{label}: not valid JSON: {exc}")
            continue

        if path.name.startswith("valid-"):
            valid += 1
            envelope_errors = list(validator.iter_errors(instance))
            for error in sorted(envelope_errors, key=lambda e: e.message):
                errors.append(f"{label}: expected valid, {error.message}")
            if not envelope_errors:
                errors.extend(
                    check_payload_binding(
                        label, instance, index, namespaces, validators
                    )
                )
        elif path.name.startswith("invalid-"):
            invalid += 1
            if not list(validator.iter_errors(instance)):
                errors.append(
                    f"{label}: expected invalid, but the envelope schema accepts it"
                )
        else:
            errors.append(f"{label}: example name must start with valid- or invalid-")

    if valid == 0:
        errors.append(f"no valid-*.json examples under {relative(EXAMPLES_DIR)}")
    if invalid == 0:
        errors.append(f"no invalid-*.json examples under {relative(EXAMPLES_DIR)}")

    status = "OK" if not errors else "FAILED"
    print(
        f"Event schemas {status}: {len(schema_paths)} schema(s), "
        f"{valid} valid and {invalid} invalid example(s), "
        f"{len(index)} payload binding(s)"
    )
    return errors


def required_lists(document) -> dict[tuple[str, ...], set[str]]:
    found: dict[tuple[str, ...], set[str]] = {}

    def walk(node, pointer: tuple[str, ...]) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                child = pointer + (str(key),)
                if key == "required" and isinstance(value, list):
                    found[child] = set(value)
                walk(value, child)
        elif isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, pointer + (str(index),))

    walk(document, ())
    return found


def compare_breaking(base, current) -> list[str]:
    errors: list[str] = []
    base_paths = base.get("paths") or {}
    current_paths = current.get("paths") or {}

    for path, operations in base_paths.items():
        if path not in current_paths:
            errors.append(f"path removed: {path}")
            continue
        if isinstance(operations, dict):
            for method in operations:
                if method in HTTP_METHODS and method not in current_paths[path]:
                    errors.append(f"operation removed: {method.upper()} {path}")

    base_required = required_lists(base)
    current_required = required_lists(current)
    for pointer, fields in base_required.items():
        location = "/".join(pointer) or "/"
        if pointer not in current_required:
            errors.append(f"required-field list removed at {location}")
            continue

        removed = fields - current_required[pointer]
        if removed:
            errors.append(
                f"required fields removed at {location}: {', '.join(sorted(removed))}"
            )

    return errors


def git_show(ref: str, path: str) -> str | None:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path}"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout if result.returncode == 0 else None


def check_version_bump(base_ref: str) -> list[str]:
    verify = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", base_ref],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if verify.returncode != 0:
        return [f"base ref not found: {base_ref}"]

    errors: list[str] = []
    for path in openapi_paths():
        label = relative(path)
        base_text = git_show(base_ref, label)
        if base_text is None:
            continue

        current_text = path.read_text(encoding="utf-8")
        if base_text == current_text:
            continue

        try:
            # The base revision is history: it may contain a duplicate key that
            # an earlier PR merged. Compare against what that revision actually
            # rendered instead of failing every later PR that touches the file.
            base_spec = yaml.safe_load(base_text)
        except yaml.YAMLError as exc:
            errors.append(f"{label}: cannot compare the base version: {exc}")
            continue

        try:
            current_spec = load_yaml(path)
        except (yaml.YAMLError, DuplicateKeyError):
            # validate_openapi already reported this file.
            continue

        base_version = (base_spec.get("info") or {}).get("version")
        current_version = (current_spec.get("info") or {}).get("version")
        if base_version != current_version:
            print(f"Version bump OK: {label} {base_version} -> {current_version}")
            continue

        for finding in compare_breaking(base_spec, current_spec):
            errors.append(
                f"{label}: breaking change without an info.version bump "
                f"({base_version}): {finding}"
            )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-ref",
        help="git ref to compare for breaking OpenAPI changes (pull requests)",
    )
    args = parser.parse_args()

    try:
        envelope = load_contract(ENVELOPE_SCHEMA)
        Draft202012Validator.check_schema(envelope)
    except Exception as exc:  # noqa: BLE001 - fail with the schema's message
        print(f"{relative(ENVELOPE_SCHEMA)}: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    errors: list[str] = []
    errors.extend(validate_openapi(envelope))
    errors.extend(validate_events(envelope))
    if args.base_ref:
        errors.extend(check_version_bump(args.base_ref))

    if errors:
        print("Contract validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1

    print("Contracts validation OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
