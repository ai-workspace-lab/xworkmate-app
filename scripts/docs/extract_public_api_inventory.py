#!/usr/bin/env python3
"""Extract public API inventory for XWorkmate engineering docs.

This script intentionally stays lightweight:
- It only scans source files that define the public engineering surface.
- It extracts top-level public symbols and compact signatures.
- It does not attempt semantic explanation or method-level expansion.
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = REPO_ROOT / "docs" / "architecture" / "public-api" / "_generated"

TARGETS = (
    "lib/app",
    "lib/runtime",
    "lib/models",
    "lib/features",
    "lib/theme",
    "rust/src",
)

COVERAGE_PREFIXES = (
    "lib/app",
    "lib/runtime",
    "lib/models",
    "lib/features/assistant",
    "lib/features/settings",
    "lib/features/mobile",
    "lib/theme",
    "rust/src",
)

DART_GLOB = "*.dart"
RUST_GLOB = "*.rs"


@dataclass(frozen=True)
class SymbolRecord:
    language: str
    path: str
    line: int
    kind: str
    name: str
    signature: str


def repo_relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def normalize_signature(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip())


def iter_target_files() -> list[Path]:
    files: list[Path] = []
    for target in TARGETS:
        root = REPO_ROOT / target
        if not root.exists():
            continue
        pattern = DART_GLOB if root.parts[-1] != "src" else RUST_GLOB
        files.extend(sorted(root.rglob(pattern)))
    return files


def extract_symbols(path: Path) -> list[SymbolRecord]:
    if path.suffix == ".dart":
        return extract_dart_symbols(path)
    if path.suffix == ".rs":
        return extract_rust_symbols(path)
    return []


def extract_dart_symbols(path: Path) -> list[SymbolRecord]:
    lines = path.read_text(encoding="utf-8").splitlines()
    symbols: list[SymbolRecord] = []
    index = 0

    type_patterns = (
        ("abstract interface", re.compile(r"^abstract\s+class\s+([A-Za-z]\w*)\b")),
        ("class", re.compile(r"^class\s+([A-Za-z]\w*)\b")),
        ("mixin", re.compile(r"^mixin\s+([A-Za-z]\w*)\b")),
        ("enum", re.compile(r"^enum\s+([A-Za-z]\w*)\b")),
        ("typedef", re.compile(r"^typedef\s+([A-Za-z]\w*)\b")),
        ("extension", re.compile(r"^extension\s+([A-Za-z]\w*)\b")),
    )
    function_pattern = re.compile(
        r"^(?:[A-Za-z_<>{}\[\]\?.,\s]+)\s+([A-Za-z]\w*)\s*\("
    )

    while index < len(lines):
        raw_line = lines[index]
        stripped = raw_line.strip()
        if not stripped or raw_line.startswith((" ", "\t")):
            index += 1
            continue
        if stripped.startswith(("//", "/*", "*", "@", "import ", "export ", "part ")):
            index += 1
            continue
        if stripped.startswith(("const ", "final ", "var ")):
            index += 1
            continue

        matched = False
        for kind, pattern in type_patterns:
            result = pattern.match(stripped)
            if not result:
                continue
            name = result.group(1)
            if name.startswith("_"):
                matched = True
                break
            signature, consumed = collect_signature(lines, index)
            symbols.append(
                SymbolRecord(
                    language="dart",
                    path=repo_relative(path),
                    line=index + 1,
                    kind=kind,
                    name=name,
                    signature=signature,
                )
            )
            index += consumed
            matched = True
            break
        if matched:
            continue

        if stripped.startswith(
            (
                "if ",
                "for ",
                "while ",
                "switch ",
                "return ",
                "assert ",
                "throw ",
                "try ",
            )
        ):
            index += 1
            continue

        function_match = function_pattern.match(stripped)
        if function_match:
            name = function_match.group(1)
            if not name.startswith("_"):
                signature, consumed = collect_signature(lines, index)
                symbols.append(
                    SymbolRecord(
                        language="dart",
                        path=repo_relative(path),
                        line=index + 1,
                        kind="top-level function",
                        name=name,
                        signature=signature,
                    )
                )
                index += consumed
                continue

        index += 1

    return symbols


def collect_signature(lines: list[str], start: int) -> tuple[str, int]:
    chunk: list[str] = []
    paren_balance = 0
    consumed = 0
    while start + consumed < len(lines):
        line = lines[start + consumed].strip()
        chunk.append(line)
        paren_balance += line.count("(") - line.count(")")
        consumed += 1
        if paren_balance <= 0 and (
            "{" in line or line.endswith(";") or "=>" in line
        ):
            break
    return normalize_signature(" ".join(chunk)), consumed


def extract_rust_symbols(path: Path) -> list[SymbolRecord]:
    lines = path.read_text(encoding="utf-8").splitlines()
    symbols: list[SymbolRecord] = []
    type_patterns = (
        ("struct", re.compile(r"^pub\s+struct\s+([A-Za-z]\w*)\b")),
        ("enum", re.compile(r"^pub\s+enum\s+([A-Za-z]\w*)\b")),
    )
    ffi_pattern = re.compile(r'^pub\s+unsafe\s+extern\s+"C"\s+fn\s+([A-Za-z]\w*)\s*\(')

    index = 0
    while index < len(lines):
        stripped = lines[index].strip()
        if not stripped or lines[index].startswith((" ", "\t")):
            index += 1
            continue
        matched = False
        for kind, pattern in type_patterns:
            result = pattern.match(stripped)
            if result:
                signature, consumed = collect_signature(lines, index)
                symbols.append(
                    SymbolRecord(
                        language="rust",
                        path=repo_relative(path),
                        line=index + 1,
                        kind=kind,
                        name=result.group(1),
                        signature=signature,
                    )
                )
                index += consumed
                matched = True
                break
        if matched:
            continue

        ffi_match = ffi_pattern.match(stripped)
        if ffi_match:
            signature, consumed = collect_signature(lines, index)
            symbols.append(
                SymbolRecord(
                    language="rust",
                    path=repo_relative(path),
                    line=index + 1,
                    kind="FFI function",
                    name=ffi_match.group(1),
                    signature=signature,
                )
            )
            index += consumed
            continue

        index += 1
    return symbols


def build_inventory(symbols: list[SymbolRecord]) -> dict:
    files = iter_target_files()
    files_by_group: dict[str, list[dict]] = defaultdict(list)
    symbol_counts_by_group: dict[str, int] = defaultdict(int)
    file_counts_by_group: dict[str, int] = defaultdict(int)

    symbols_by_path: dict[str, list[SymbolRecord]] = defaultdict(list)
    for symbol in symbols:
        symbols_by_path[symbol.path].append(symbol)

    for file_path in files:
        relative = repo_relative(file_path)
        parts = relative.split("/")
        group = "/".join(parts[:2]) if len(parts) >= 2 else relative
        file_counts_by_group[group] += 1
        file_symbols = sorted(symbols_by_path[relative], key=lambda item: item.line)
        symbol_counts_by_group[group] += len(file_symbols)
        files_by_group[group].append(
            {
                "path": relative,
                "language": "dart" if file_path.suffix == ".dart" else "rust",
                "symbolCount": len(file_symbols),
                "symbols": [asdict(item) for item in file_symbols],
            }
        )

    groups = []
    for group in sorted(files_by_group):
        groups.append(
            {
                "group": group,
                "fileCount": file_counts_by_group[group],
                "symbolCount": symbol_counts_by_group[group],
                "files": files_by_group[group],
            }
        )

    scope_summaries = []
    all_paths = [repo_relative(path) for path in files]
    for prefix in COVERAGE_PREFIXES:
        scope_files = [
            item
            for item in all_paths
            if item == prefix or item.startswith(f"{prefix}/")
        ]
        scope_symbol_count = sum(
            1
            for symbol in symbols
            if symbol.path == prefix or symbol.path.startswith(f"{prefix}/")
        )
        scope_summaries.append(
            {
                "scope": prefix,
                "fileCount": len(scope_files),
                "symbolCount": scope_symbol_count,
            }
        )

    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "targets": list(TARGETS),
        "coverageScopes": scope_summaries,
        "totals": {
            "fileCount": len(files),
            "symbolCount": len(symbols),
        },
        "groups": groups,
    }


def render_markdown(inventory: dict) -> str:
    lines: list[str] = [
        "# Public Symbol Inventory",
        "",
        "> Auto-generated by `scripts/docs/extract_public_api_inventory.py`.",
        ">",
        "> Scope: `lib/app`, `lib/runtime`, `lib/models`, `lib/features/**`, `lib/theme`, `rust/src`.",
        "> Excludes private `_` symbols and non-top-level Dart members.",
        "",
        f"- Generated at: `{inventory['generatedAt']}`",
        f"- Files scanned: `{inventory['totals']['fileCount']}`",
        f"- Public symbols extracted: `{inventory['totals']['symbolCount']}`",
        "",
        "## Group Summary",
        "",
        "| Group | Files | Public Symbols |",
        "| --- | ---: | ---: |",
    ]
    for group in inventory["groups"]:
        lines.append(
            f"| `{group['group']}` | {group['fileCount']} | {group['symbolCount']} |"
        )

    lines.extend(
        [
            "",
            "## Coverage Scope Summary",
            "",
            "| Scope | Files | Public Symbols |",
            "| --- | ---: | ---: |",
        ]
    )
    for scope in inventory["coverageScopes"]:
        lines.append(
            f"| `{scope['scope']}` | {scope['fileCount']} | {scope['symbolCount']} |"
        )

    for group in inventory["groups"]:
        lines.extend(
            [
                "",
                f"## {group['group']}",
                "",
                f"- Files: `{group['fileCount']}`",
                f"- Public symbols: `{group['symbolCount']}`",
            ]
        )
        for file_entry in group["files"]:
            lines.extend(
                [
                    "",
                    f"### `{file_entry['path']}`",
                    "",
                    f"- Language: `{file_entry['language']}`",
                    f"- Public symbols: `{file_entry['symbolCount']}`",
                ]
            )
            if not file_entry["symbols"]:
                lines.extend(["", "_No extracted public top-level symbols._"])
                continue
            lines.extend(
                [
                    "",
                    "| Line | Kind | Name | Signature |",
                    "| ---: | --- | --- | --- |",
                ]
            )
            for symbol in file_entry["symbols"]:
                signature = symbol["signature"].replace("|", "\\|")
                lines.append(
                    f"| {symbol['line']} | `{symbol['kind']}` | `{symbol['name']}` | `{signature}` |"
                )

    lines.append("")
    return "\n".join(lines)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    files = iter_target_files()
    symbols: list[SymbolRecord] = []
    for file_path in files:
        symbols.extend(extract_symbols(file_path))
    inventory = build_inventory(symbols)
    markdown = render_markdown(inventory)

    json_path = OUTPUT_DIR / "public-symbol-inventory.json"
    md_path = OUTPUT_DIR / "public-symbol-inventory.md"

    json_path.write_text(
        json.dumps(inventory, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    md_path.write_text(markdown, encoding="utf-8")

    print(f"Wrote {repo_relative(json_path)}")
    print(f"Wrote {repo_relative(md_path)}")
    print(
        f"Scanned {inventory['totals']['fileCount']} files, extracted {inventory['totals']['symbolCount']} public symbols."
    )


if __name__ == "__main__":
    main()
