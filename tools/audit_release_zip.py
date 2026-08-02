#!/usr/bin/env python3
"""Audit installable-mod and source ZIPs before attaching them to a release."""

from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import re
import sys
import zipfile

from audit_public_tree import (
    ALLOWED_EXACT,
    ALLOWED_PATTERNS,
    PRIVATE_PATHS,
    REQUIRED,
    looks_like_game_boy_rom,
)


MOD_EXACT = {
    ".modkit/pack.json",
    "CHANGELOG.md",
    "CREDITS.md",
    "FONT_WORKFLOW.md",
    "README.md",
    "TERMINOLOGY.md",
    "assets/font/fusion-pixel-8px-monospaced-zh_hans.bdf",
    "assets/font/quan.bdf",
    "lang/charmap.lua",
    "lang/dialogue.lua",
    "lang/dialogue_rb.lua",
    "lang/font.lua",
    "lang/item_names.lua",
    "lang/move_names.lua",
    "lang/naming.lua",
    "lang/species_names.lua",
    "lang/status_labels.lua",
    "lang/strings.lua",
    "lang/trainer_names.lua",
    "lang/type_names.lua",
    "LICENSES/FusionPixel-OFL-1.1.txt",
    "LICENSES/Gen1Recomp-MIT.txt",
    "LICENSES/QuanPixel-OFL-1.1.txt",
    "main.lua",
    "manifest.json",
    "tools/build_zh_cn_font.py",
}
MOD_PATTERNS = (re.compile(r"lang/font/zh_cn_\d{3}\.png"),)
MOD_REQUIRED = {
    ".modkit/pack.json",
    "CREDITS.md",
    "lang/dialogue.lua",
    "lang/dialogue_rb.lua",
    "LICENSES/FusionPixel-OFL-1.1.txt",
    "LICENSES/Gen1Recomp-MIT.txt",
    "LICENSES/QuanPixel-OFL-1.1.txt",
    "main.lua",
    "manifest.json",
    "tools/build_zh_cn_font.py",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("mod", "source"))
    parser.add_argument("archive", type=Path)
    return parser.parse_args()


def strip_source_prefix(names: list[str]) -> tuple[list[str], str | None]:
    heads = {PurePosixPath(name).parts[0] for name in names if PurePosixPath(name).parts}
    if len(heads) != 1:
        return names, None
    prefix = next(iter(heads))
    stripped = [name[len(prefix) + 1 :] for name in names if name != prefix]
    return stripped, prefix


def allowed(name: str, exact: set[str], patterns: tuple[re.Pattern[str], ...]) -> bool:
    return name in exact or any(pattern.fullmatch(name) for pattern in patterns)


def main() -> int:
    args = parse_args()
    archive = args.archive.resolve()
    if not archive.is_file():
        print(f"ERROR archive does not exist: {archive}", file=sys.stderr)
        return 2

    problems: list[str] = []
    with zipfile.ZipFile(archive) as bundle:
        corrupt = bundle.testzip()
        if corrupt:
            problems.append(f"CRC failure: {corrupt}")
        all_infos = bundle.infolist()
        for info in all_infos:
            name = info.filename
            pure = PurePosixPath(name)
            if name.startswith(("/", "\\")) or "\\" in name or ".." in pure.parts:
                problems.append(f"unsafe archive path: {name}")

        infos = [info for info in all_infos if not info.is_dir()]
        raw_names = [info.filename for info in infos]

        if len(set(raw_names)) != len(raw_names):
            problems.append("duplicate archive member name")

        if args.kind == "source":
            names, prefix = strip_source_prefix(raw_names)
            if prefix is None:
                problems.append("source archive must have one top-level version directory")
            elif prefix in raw_names:
                problems.append(
                    "source archive contains a non-directory member named as its prefix"
                )
            exact, patterns, required = ALLOWED_EXACT, ALLOWED_PATTERNS, REQUIRED
        else:
            names, prefix = raw_names, None
            exact, patterns, required = MOD_EXACT, MOD_PATTERNS, MOD_REQUIRED

        normalized: dict[str, zipfile.ZipInfo] = {}
        for info, raw_name in zip(infos, raw_names):
            name = raw_name[len(prefix) + 1 :] if prefix else raw_name
            if not name:
                continue
            normalized[name] = info
            if not allowed(name, exact, patterns):
                problems.append(f"path is outside the {args.kind} ZIP allowlist: {name}")
            if "worksheet" in name.lower():
                problems.append(f"worksheet-like path is forbidden: {name}")

            data = bundle.read(info)
            if looks_like_game_boy_rom(data):
                problems.append(f"Game Boy ROM header detected: {name}")
            if name.lower().endswith(".png"):
                continue
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                problems.append(f"non-PNG archive member is not UTF-8: {name}")
                continue
            for pattern in PRIVATE_PATHS:
                if pattern.search(text):
                    problems.append(f"personal or machine-specific absolute path: {name}")
                    break

        for missing in sorted(required - normalized.keys()):
            problems.append(f"required {args.kind} ZIP member is missing: {missing}")

    if problems:
        for problem in sorted(set(problems)):
            print(f"ERROR {problem}", file=sys.stderr)
        return 1
    print(f"{args.kind} ZIP audit passed: {len(normalized)} allowlisted file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
