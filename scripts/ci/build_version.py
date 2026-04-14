#!/usr/bin/env python3
"""Resolve platform-safe build versions from pubspec.yaml.

This repo keeps prerelease semantics in the pubspec version, for example:
  1.0.0-beta.2+4

Packaging metadata across Apple/Linux/Windows must use the numeric release
portion only, while display-facing surfaces can keep the prerelease label.
"""

from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
from pathlib import Path


VERSION_PATTERN = re.compile(r"^version:\s*([^\n]+)", re.MULTILINE)
RELEASE_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")


def parse_pubspec_version(pubspec_path: Path) -> dict[str, str]:
    text = pubspec_path.read_text(encoding="utf-8")
    match = VERSION_PATTERN.search(text)
    if match is None:
        raise ValueError(f"Unable to find version in {pubspec_path}")

    raw_version = match.group(1).strip()
    if not raw_version:
        raise ValueError(f"Version in {pubspec_path} is empty")

    if "+" in raw_version:
        display_version, build_number = raw_version.split("+", 1)
    else:
        display_version, build_number = raw_version, "1"

    display_version = display_version.strip()
    build_number = build_number.strip()
    platform_release_version = display_version.split("-", 1)[0].strip()

    if not RELEASE_PATTERN.fullmatch(platform_release_version):
        raise ValueError(
            "Expected pubspec version to expose a three-part numeric release "
            f"prefix before prerelease/build metadata, got: {raw_version}"
        )

    if not build_number.isdigit():
        raise ValueError(f"Expected numeric build number in pubspec version, got: {raw_version}")

    return {
        "raw_version": raw_version,
        "display_version": display_version,
        "platform_release_version": platform_release_version,
        "build_number": build_number,
    }


def emit_shell(values: dict[str, str]) -> None:
    for key, value in values.items():
        env_key = key.upper()
        print(f"{env_key}={shlex.quote(value)}")


def emit_json(values: dict[str, str]) -> None:
    print(json.dumps(values))


def emit_github_output(values: dict[str, str]) -> None:
    for key, value in values.items():
        print(f"{key}={value}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--pubspec",
        default="pubspec.yaml",
        help="Path to pubspec.yaml",
    )
    parser.add_argument(
        "--format",
        choices=("shell", "json", "github-output"),
        default="json",
        help="Output format",
    )
    args = parser.parse_args()

    values = parse_pubspec_version(Path(args.pubspec))

    if args.format == "shell":
        emit_shell(values)
    elif args.format == "github-output":
        emit_github_output(values)
    else:
        emit_json(values)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - CLI failure path
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
