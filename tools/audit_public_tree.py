#!/usr/bin/env python3
"""Audit the exact files that may be published from this repository."""

from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys


ALLOWED_EXACT = {
    ".gitattributes",
    ".github/workflows/quality.yml",
    ".gitignore",
    "README.md",
    "mods/zh_cn/.luarc.json",
    "mods/zh_cn/.modkitignore",
    "mods/zh_cn/CHANGELOG.md",
    "mods/zh_cn/CREDITS.md",
    "mods/zh_cn/FONT_WORKFLOW.md",
    "mods/zh_cn/README.md",
    "mods/zh_cn/TERMINOLOGY.md",
    "mods/zh_cn/TRANSLATING.md",
    "mods/zh_cn/assets/font/README.md",
    "mods/zh_cn/assets/font/fusion-pixel-8px-monospaced-zh_hans.bdf",
    "mods/zh_cn/assets/font/fusion-pixel-8px-proportional-zh_hans.bdf",
    "mods/zh_cn/assets/font/quan.bdf",
    "mods/zh_cn/lang/charmap.lua",
    "mods/zh_cn/lang/dialogue.lua",
    "mods/zh_cn/lang/dialogue_rb.lua",
    "mods/zh_cn/lang/font.lua",
    "mods/zh_cn/lang/item_names.lua",
    "mods/zh_cn/lang/move_names.lua",
    "mods/zh_cn/lang/naming.lua",
    "mods/zh_cn/lang/species_names.lua",
    "mods/zh_cn/lang/status_labels.lua",
    "mods/zh_cn/lang/strings.lua",
    "mods/zh_cn/lang/trainer_names.lua",
    "mods/zh_cn/lang/type_names.lua",
    "mods/zh_cn/LICENSES/FusionPixel-OFL-1.1.txt",
    "mods/zh_cn/LICENSES/Gen1Recomp-MIT.txt",
    "mods/zh_cn/LICENSES/QuanPixel-OFL-1.1.txt",
    "mods/zh_cn/main.lua",
    "mods/zh_cn/manifest.json",
    "mods/zh_cn/tools/build_zh_cn_font.py",
    "tests/drivers/zh_cn_smoke_test.lua",
    "tools/audit_public_tree.py",
    "tools/audit_release_zip.py",
    "tools/check_zh_cn_dialogue.py",
}
ALLOWED_PATTERNS = (re.compile(r"mods/zh_cn/lang/font/zh_cn_\d{3}\.png"),)
REQUIRED = {
    "README.md",
    "mods/zh_cn/CREDITS.md",
    "mods/zh_cn/LICENSES/FusionPixel-OFL-1.1.txt",
    "mods/zh_cn/LICENSES/Gen1Recomp-MIT.txt",
    "mods/zh_cn/LICENSES/QuanPixel-OFL-1.1.txt",
    "mods/zh_cn/lang/dialogue.lua",
    "mods/zh_cn/lang/dialogue_rb.lua",
    "mods/zh_cn/main.lua",
    "mods/zh_cn/manifest.json",
    "mods/zh_cn/tools/build_zh_cn_font.py",
}
PRIVATE_PATHS = (
    re.compile(r"(?i)(?<![A-Za-z0-9])[A-Z]:[\\/]"),
    re.compile(r"(?i)(?:^|[\s\"'(])/(?:Users|home)/[^/\s]+/"),
)


def candidate_paths(root: Path) -> list[Path]:
    """Return tracked plus non-ignored untracked files: the commit candidates."""

    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root,
        check=True,
        capture_output=True,
    )
    return [root / item.decode("utf-8") for item in result.stdout.split(b"\0") if item]


def allowed(rel: str) -> bool:
    return rel in ALLOWED_EXACT or any(pattern.fullmatch(rel) for pattern in ALLOWED_PATTERNS)


def looks_like_game_boy_rom(data: bytes) -> bool:
    """Recognize a renamed GB/GBC image using its standard header checksum."""

    if len(data) < 32 * 1024 or len(data) % (16 * 1024) != 0 or len(data) <= 0x14D:
        return False
    checksum = 0
    for value in data[0x134:0x14D]:
        checksum = (checksum - value - 1) & 0xFF
    return checksum == data[0x14D]


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    problems: list[str] = []
    paths = candidate_paths(root)
    relative = {path.relative_to(root).as_posix() for path in paths}

    for missing in sorted(REQUIRED - relative):
        problems.append(f"required release source is missing: {missing}")

    for path in paths:
        rel = path.relative_to(root).as_posix()
        if not allowed(rel):
            problems.append(f"path is outside the explicit public allowlist: {rel}")
            continue
        if "worksheet" in rel.lower():
            problems.append(f"worksheet-like path is forbidden: {rel}")
        if path.is_symlink():
            problems.append(f"symbolic links are not permitted: {rel}")
            continue
        if not path.is_file():
            problems.append(f"publish candidate is not a regular file: {rel}")
            continue

        data = path.read_bytes()
        if looks_like_game_boy_rom(data):
            problems.append(f"Game Boy ROM header detected: {rel}")

        # PNG is the only allowed binary format. Every other permitted source
        # file must be UTF-8 and is scanned for machine-specific absolute paths.
        if path.suffix.lower() == ".png":
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            problems.append(f"non-PNG source file is not UTF-8: {rel}")
            continue
        for pattern in PRIVATE_PATHS:
            if pattern.search(text):
                problems.append(f"personal or machine-specific absolute path: {rel}")
                break

    if problems:
        for problem in sorted(set(problems)):
            print(f"ERROR {problem}", file=sys.stderr)
        return 1

    print(
        f"public-tree audit passed: {len(paths)} allowlisted publish-candidate file(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
