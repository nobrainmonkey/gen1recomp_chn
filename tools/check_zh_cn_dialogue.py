#!/usr/bin/env python3
"""Check zh_cn dialogue against locally imported Red, Blue, and Yellow text.

This tool contains no original game text. Pass one or more local sources made
from ROMs you legally own, for example::

    python tools/check_zh_cn_dialogue.py \
        --source red=path/to/red/data/generated/text.lua \
        --source blue=path/to/blue/data/generated/text.lua \
        --source yellow=path/to/yellow/data/generated/text.lua

A tab-separated ``dialogue.txt`` worksheet is accepted as well as generated
``text.lua``. Red and Blue are checked against the shared catalogue plus
``dialogue_rb.lua``; Yellow is checked only against the shared catalogue.
"""

from __future__ import annotations

import argparse
from collections import Counter
import importlib.util
from pathlib import Path
import re
import sys


CONTROL_CHARS = "\n\v\f"
BRACE_TOKEN = re.compile(r"\{[^{}]+\}")
FORMAT_TOKEN = re.compile(r"%(?!%)(?:[-+ #0]*\d*(?:\.\d+)?)?[A-Za-z]")
VERSIONS = ("red", "blue", "yellow")


def load_font_builder(repo_root: Path):
    path = repo_root / "mods" / "zh_cn" / "tools" / "build_zh_cn_font.py"
    spec = importlib.util.spec_from_file_location("zh_cn_font_builder", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load Lua lexer from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def catalog_entries(builder, path: Path) -> tuple[dict[str, str], dict[str, int]]:
    tokens = builder.lua_tokens(path.read_text(encoding="utf-8"), path)
    values: dict[str, str] = {}
    lines: dict[str, int] = {}
    for index in range(len(tokens) - 4):
        row = tokens[index : index + 5]
        if not (
            row[0].kind == "symbol"
            and row[0].value == "["
            and row[1].kind == "string"
            and row[2].kind == "symbol"
            and row[2].value == "]"
            and row[3].kind == "symbol"
            and row[3].value == "="
            and row[4].kind == "string"
        ):
            continue
        key = row[1].value
        if key in values:
            raise RuntimeError(f"{path}:{row[1].line}: duplicate key {key!r}")
        values[key] = row[4].value
        lines[key] = row[4].line
    return values, lines


def worksheet_entries(builder, path: Path) -> dict[str, str]:
    # Local worksheets encode ROM controls as two-digit decimal escapes. Avoid
    # Lua's three-digit escape rule consuming a following floor/route digit.
    text = path.read_text(encoding="utf-8")
    text = text.replace("\\11", "\\v").replace("\\12", "\\f")
    tokens = [token for token in builder.lua_tokens(text, path) if token.kind == "string"]
    if len(tokens) % 2:
        raise RuntimeError(f"{path}: expected key/source string pairs")
    values: dict[str, str] = {}
    for index in range(0, len(tokens), 2):
        key, source = tokens[index], tokens[index + 1]
        if key.value in values:
            raise RuntimeError(f"{path}:{key.line}: duplicate key {key.value!r}")
        values[key.value] = source.value
    return values


def generated_entries(builder, path: Path) -> dict[str, str]:
    """Read generated text.lua, whose table normally uses bare identifier keys."""

    tokens = builder.lua_tokens(path.read_text(encoding="utf-8"), path)
    values: dict[str, str] = {}
    for index, token in enumerate(tokens):
        key: str | None = None
        source = None
        if (
            token.kind == "identifier"
            and index + 2 < len(tokens)
            and tokens[index + 1].kind == "symbol"
            and tokens[index + 1].value == "="
            and tokens[index + 2].kind == "string"
        ):
            key, source = token.value, tokens[index + 2]
        elif index + 4 < len(tokens):
            row = tokens[index : index + 5]
            if (
                row[0].kind == "symbol"
                and row[0].value == "["
                and row[1].kind == "string"
                and row[2].kind == "symbol"
                and row[2].value == "]"
                and row[3].kind == "symbol"
                and row[3].value == "="
                and row[4].kind == "string"
            ):
                key, source = row[1].value, row[4]
        if key is None or source is None:
            continue
        if key in values:
            raise RuntimeError(f"{path}:{source.line}: duplicate key {key!r}")
        values[key] = source.value
    return values


def source_entries(builder, path: Path) -> dict[str, str]:
    if not path.is_file():
        raise RuntimeError(f"source file does not exist: {path}")
    if path.suffix.lower() == ".lua":
        return generated_entries(builder, path)
    return worksheet_entries(builder, path)


def controls(text: str) -> list[str]:
    return [char for char in text if char in CONTROL_CHARS]


def visible_static_width(text: str) -> int:
    return len(FORMAT_TOKEN.sub("", BRACE_TOKEN.sub("", text)))


def source_spec(value: str) -> tuple[str, Path]:
    version, separator, raw_path = value.partition("=")
    version = version.lower().strip()
    if not separator or version not in VERSIONS or not raw_path.strip():
        choices = ", ".join(VERSIONS)
        raise argparse.ArgumentTypeError(
            f"expected VERSION=PATH where VERSION is one of: {choices}"
        )
    return version, Path(raw_path.strip()).expanduser()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        action="append",
        default=[],
        type=source_spec,
        metavar="VERSION=PATH",
        help="local generated text.lua or dialogue worksheet; repeat per version",
    )
    parser.add_argument("--max-line", type=int, default=18)
    parser.add_argument("--limit", type=int, default=200)
    parser.add_argument(
        "--strict-controls",
        action="store_true",
        help="require translated line/scroll/page markers to match exactly",
    )
    return parser.parse_args()


def check_translation(
    *,
    problems: list[str],
    where: str,
    source: str,
    value: str,
    max_line: int,
    strict_controls: bool,
    check_width: bool = True,
) -> bool:
    if value == "":
        problems.append(f"{where}: empty translation")
        return False
    source_placeholders = BRACE_TOKEN.findall(source)
    value_placeholders = BRACE_TOKEN.findall(value)
    if Counter(value_placeholders) != Counter(source_placeholders):
        problems.append(
            f"{where}: placeholder mismatch "
            f"{source_placeholders!r} -> {value_placeholders!r}"
        )
    source_formats = FORMAT_TOKEN.findall(source)
    value_formats = FORMAT_TOKEN.findall(value)
    if value_formats != source_formats:
        problems.append(
            f"{where}: format-token mismatch {source_formats!r} -> {value_formats!r}"
        )
    if value.count("\f") != source.count("\f"):
        problems.append(
            f"{where}: page-break count mismatch "
            f"{source.count(chr(12))} -> {value.count(chr(12))}"
        )
    if strict_controls and controls(value) != controls(source):
        problems.append(
            f"{where}: control mismatch {controls(source)!r} -> {controls(value)!r}"
        )
    if check_width:
        for segment in re.split(f"[{CONTROL_CHARS}]", value):
            width = visible_static_width(segment)
            if width > max_line:
                problems.append(
                    f"{where}: static line width {width} exceeds {max_line}: {segment!r}"
                )
    return True


def main() -> int:
    args = parse_args()
    if not args.source:
        print(
            "error: pass at least one --source VERSION=PATH made from your own ROM",
            file=sys.stderr,
        )
        return 2

    source_paths: dict[str, Path] = {}
    for version, path in args.source:
        if version in source_paths:
            print(f"error: duplicate --source for {version}", file=sys.stderr)
            return 2
        source_paths[version] = path.resolve()

    repo_root = Path(__file__).resolve().parent.parent
    lang_dir = repo_root / "mods" / "zh_cn" / "lang"
    builder = load_font_builder(repo_root)
    shared, shared_lines = catalog_entries(builder, lang_dir / "dialogue.lua")
    rb_path = lang_dir / "dialogue_rb.lua"
    rb, rb_lines = catalog_entries(builder, rb_path) if rb_path.is_file() else ({}, {})
    strings, string_lines = catalog_entries(builder, lang_dir / "strings.lua")

    problems: list[str] = []
    source_sets: dict[str, dict[str, str]] = {}
    for version in VERSIONS:
        if version not in source_paths:
            continue
        sources = source_entries(builder, source_paths[version])
        source_sets[version] = sources
        effective = dict(shared)
        effective_lines = dict(shared_lines)
        effective_file = {key: "dialogue.lua" for key in shared}
        if version in {"red", "blue"}:
            effective.update(rb)
            effective_lines.update(rb_lines)
            effective_file.update({key: "dialogue_rb.lua" for key in rb})

        missing = sorted(sources.keys() - effective.keys())
        for key in missing:
            problems.append(f"{version}: missing catalog key {key}")

        translated_count = 0
        for key, source in sources.items():
            if key not in effective:
                continue
            where = f"{version}:{effective_file[key]}:{effective_lines[key]} {key}"
            if check_translation(
                problems=problems,
                where=where,
                source=source,
                value=effective[key],
                max_line=args.max_line,
                strict_controls=args.strict_controls,
            ):
                translated_count += 1

        print(
            f"zh_cn {version}: {translated_count}/{len(sources)} local source keys "
            f"translated ({len(effective)} effective catalog entries)"
        )

    # Every R/B override should correspond to a real R/B key when an R/B source
    # was supplied. This catches stale or mistyped IDs without requiring either
    # game's English text to live in the repository.
    rb_source_keys: set[str] = set()
    for version in ("red", "blue"):
        rb_source_keys.update(source_sets.get(version, {}))
    if rb_source_keys:
        for key in sorted(rb.keys() - rb_source_keys):
            problems.append(f"dialogue_rb.lua: override absent from supplied R/B source: {key}")

    # Engine string keys are their own source strings and are not ROM script.
    for source, value in strings.items():
        check_translation(
            problems=problems,
            where=f"strings.lua:{string_lines[source]} {source!r}",
            source=source,
            value=value,
            max_line=args.max_line,
            strict_controls=args.strict_controls,
            check_width=False,
        )
    print(f"zh_cn interface strings: {len(strings)} catalog entries checked")

    if problems:
        for problem in problems[: args.limit]:
            print(f"ERROR {problem}", file=sys.stderr)
        if len(problems) > args.limit:
            print(f"ERROR ... {len(problems) - args.limit} more problem(s)", file=sys.stderr)
        print(f"FAIL {len(problems)} translation problem(s)", file=sys.stderr)
        return 1
    print("ok zh_cn translations complete and structurally consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
