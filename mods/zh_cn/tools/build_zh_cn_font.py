#!/usr/bin/env python3
"""Build the Simplified-Chinese translation's 8x8 font pages.

The builder deliberately consumes QuanPixel's BDF rather than rasterizing its
TTF.  BDF pixels are copied verbatim into Gen1Recomp's 8x8 glyph cells, so the
result has no antialiasing, scaling, or platform-dependent font rendering.

This copy lives inside the mod so development ZIPs retain the complete font
workflow.  By default it reads ``assets/font/quan.bdf`` from the mod that
contains this script and updates that same mod::

    python tools/build_zh_cn_font.py
    python tools/build_zh_cn_font.py --check
    python tools/build_zh_cn_font.py --bdf path/to/an-8x8-font.bdf

Only non-ASCII characters in nonempty translated values are included.  ASCII
continues to use the vanilla Pokemon font.
"""

from __future__ import annotations

import argparse
import binascii
from dataclasses import dataclass
import json
from pathlib import Path
import re
import struct
import sys
import zlib


def _configure_stdio() -> None:
    """Keep Unicode paths and glyph diagnostics readable on Windows pipes."""

    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(encoding="utf-8", errors="backslashreplace")


CELL_SIZE = 8
PAGE_COLUMNS = 16
GLYPHS_PER_PAGE = 256
PAGE_SIZE = CELL_SIZE * PAGE_COLUMNS
BASE_CODE = 0x100
PAGE_NAME_RE = re.compile(r"^zh_cn_\d{3}\.png$")


class BuildError(RuntimeError):
    """An input error that should be shown without a traceback."""


@dataclass(frozen=True)
class LuaToken:
    kind: str
    value: str
    line: int


@dataclass(frozen=True)
class Glyph:
    codepoint: int
    dwidth: int
    width: int
    height: int
    x_offset: int
    y_offset: int
    rows: tuple[int, ...]
    row_bits: tuple[int, ...]


@dataclass(frozen=True)
class BdfFont:
    family: str
    version: str
    ascent: int
    descent: int
    glyphs: dict[int, Glyph]


def _long_bracket_open(text: str, pos: int) -> tuple[int, str] | None:
    """Return (content_start, closing delimiter) for a Lua long bracket."""

    if pos >= len(text) or text[pos] != "[":
        return None
    cursor = pos + 1
    while cursor < len(text) and text[cursor] == "=":
        cursor += 1
    if cursor >= len(text) or text[cursor] != "[":
        return None
    equals = text[pos + 1 : cursor]
    return cursor + 1, "]" + equals + "]"


def _decode_lua_short_string(text: str, pos: int, line: int) -> tuple[str, int, int]:
    """Decode one Lua short string; pos points at its quote."""

    quote = text[pos]
    pos += 1
    raw = bytearray()
    simple = {
        "a": 7,
        "b": 8,
        "f": 12,
        "n": 10,
        "r": 13,
        "t": 9,
        "v": 11,
        "\\": 92,
        '"': 34,
        "'": 39,
    }

    while pos < len(text):
        char = text[pos]
        if char == quote:
            try:
                return raw.decode("utf-8"), pos + 1, line
            except UnicodeDecodeError as exc:
                raise BuildError(
                    f"line {line}: Lua string is not valid UTF-8 ({exc})"
                ) from exc
        if char in "\r\n":
            raise BuildError(f"line {line}: newline in a short Lua string")
        if char != "\\":
            raw.extend(char.encode("utf-8"))
            pos += 1
            continue

        pos += 1
        if pos >= len(text):
            raise BuildError(f"line {line}: unfinished Lua escape")
        escaped = text[pos]
        if escaped in simple:
            raw.append(simple[escaped])
            pos += 1
        elif escaped.isdigit():
            end = pos
            while end < len(text) and end < pos + 3 and text[end].isdigit():
                end += 1
            value = int(text[pos:end], 10)
            if value > 255:
                raise BuildError(f"line {line}: Lua decimal escape exceeds 255")
            raw.append(value)
            pos = end
        elif escaped == "x":
            digits = text[pos + 1 : pos + 3]
            if len(digits) != 2 or not re.fullmatch(r"[0-9A-Fa-f]{2}", digits):
                raise BuildError(f"line {line}: malformed Lua hexadecimal escape")
            raw.append(int(digits, 16))
            pos += 3
        elif escaped == "u" and text.startswith("u{", pos):
            end = text.find("}", pos + 2)
            digits = text[pos + 2 : end] if end >= 0 else ""
            if not digits or not re.fullmatch(r"[0-9A-Fa-f]+", digits):
                raise BuildError(f"line {line}: malformed Lua Unicode escape")
            value = int(digits, 16)
            try:
                raw.extend(chr(value).encode("utf-8"))
            except (ValueError, UnicodeEncodeError) as exc:
                raise BuildError(f"line {line}: invalid Unicode escape U+{value:X}") from exc
            pos = end + 1
        elif escaped == "z":
            pos += 1
            while pos < len(text) and text[pos].isspace():
                if text[pos] == "\n":
                    line += 1
                pos += 1
        elif escaped == "\n":
            raw.append(10)
            line += 1
            pos += 1
        elif escaped == "\r":
            if pos + 1 < len(text) and text[pos + 1] == "\n":
                pos += 1
            raw.append(10)
            line += 1
            pos += 1
        else:
            raise BuildError(f"line {line}: unsupported Lua escape \\{escaped}")

    raise BuildError(f"line {line}: unterminated Lua string")


def lua_tokens(text: str, source: Path) -> list[LuaToken]:
    """Lex the small Lua subset used by generated translation catalogs."""

    tokens: list[LuaToken] = []
    pos = 0
    line = 1
    length = len(text)

    try:
        while pos < length:
            char = text[pos]
            if char.isspace():
                if char == "\n":
                    line += 1
                pos += 1
                continue

            if text.startswith("--", pos):
                long_comment = _long_bracket_open(text, pos + 2)
                if long_comment:
                    content_start, close = long_comment
                    end = text.find(close, content_start)
                    if end < 0:
                        raise BuildError(f"line {line}: unterminated Lua block comment")
                    line += text[pos : end + len(close)].count("\n")
                    pos = end + len(close)
                else:
                    end = text.find("\n", pos + 2)
                    pos = length if end < 0 else end
                continue

            if char in "\"'":
                start_line = line
                value, pos, line = _decode_lua_short_string(text, pos, line)
                tokens.append(LuaToken("string", value, start_line))
                continue

            long_string = _long_bracket_open(text, pos)
            if long_string:
                content_start, close = long_string
                end = text.find(close, content_start)
                if end < 0:
                    raise BuildError(f"line {line}: unterminated Lua long string")
                value = text[content_start:end]
                # Lua discards one newline immediately after the opening bracket.
                if value.startswith("\r\n"):
                    value = value[2:]
                elif value.startswith("\n") or value.startswith("\r"):
                    value = value[1:]
                tokens.append(LuaToken("string", value, line))
                line += text[pos : end + len(close)].count("\n")
                pos = end + len(close)
                continue

            if char.isalpha() or char == "_":
                end = pos + 1
                while end < length and (text[end].isalnum() or text[end] == "_"):
                    end += 1
                tokens.append(LuaToken("identifier", text[pos:end], line))
                pos = end
                continue

            tokens.append(LuaToken("symbol", char, line))
            pos += 1
    except BuildError as exc:
        raise BuildError(f"{source}: {exc}") from exc

    return tokens


def translated_values(path: Path) -> list[tuple[str, int]]:
    """Return active translated values from one generated catalog."""

    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise BuildError(f"{path}: not valid UTF-8 ({exc})") from exc
    tokens = lua_tokens(text, path)

    if path.name == "naming.lua":
        # Naming-grid cells are nested array strings rather than key/value rows.
        return [(token.value, token.line) for token in tokens if token.kind == "string"]

    values: list[tuple[str, int]] = []
    for index in range(len(tokens) - 4):
        window = tokens[index : index + 5]
        if (
            window[0].kind == "symbol"
            and window[0].value == "["
            and window[1].kind == "string"
            and window[2].kind == "symbol"
            and window[2].value == "]"
            and window[3].kind == "symbol"
            and window[3].value == "="
            and window[4].kind == "string"
        ):
            values.append((window[4].value, window[4].line))
    return values


def required_characters(lang_dir: Path) -> tuple[list[int], dict[int, list[str]]]:
    """Collect non-ASCII glyphs displayed by catalogs and mod metadata."""

    if not lang_dir.is_dir():
        raise BuildError(f"translation catalog directory does not exist: {lang_dir}")

    usages: dict[int, list[str]] = {}
    catalog_paths = sorted(
        path
        for path in lang_dir.glob("*.lua")
        if path.name not in {"font.lua", "charmap.lua"}
    )
    if not catalog_paths:
        raise BuildError(f"no translation Lua catalogs found in {lang_dir}")

    def add_value(value: str, location: str) -> None:
        if value == "":
            return
        for char in value:
            codepoint = ord(char)
            if codepoint <= 0x7F:
                continue
            locations = usages.setdefault(codepoint, [])
            if location not in locations:
                locations.append(location)

    for path in catalog_paths:
        for value, line in translated_values(path):
            add_value(value, f"{path.name}:{line}")

    # Compatibility labels and the translated log line live in the entry
    # chunk rather than a catalog, but the in-game options UI draws them with
    # the same 8x8 font.
    mod_dir = lang_dir.parent
    main_path = mod_dir / "main.lua"
    if main_path.is_file():
        try:
            main_text = main_path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            raise BuildError(f"{main_path}: not valid UTF-8 ({exc})") from exc
        for token in lua_tokens(main_text, main_path):
            if token.kind == "string":
                add_value(token.value, f"main.lua:{token.line}")

    # The mod manager displays manifest name/description through Font too.
    manifest_path = mod_dir / "manifest.json"
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise BuildError(f"{manifest_path}: invalid UTF-8 JSON ({exc})") from exc

        def walk_json(value: object, pointer: str) -> None:
            if isinstance(value, str):
                add_value(value, f"manifest.json:{pointer}")
            elif isinstance(value, list):
                for index, item in enumerate(value):
                    walk_json(item, f"{pointer}/{index}")
            elif isinstance(value, dict):
                for key in sorted(value):
                    walk_json(value[key], f"{pointer}/{key}")

        walk_json(manifest, "")

    return sorted(usages), usages


def _property_value(lines: list[str], name: str, default: str = "") -> str:
    prefix = name + " "
    for line in lines:
        if line.startswith(prefix):
            return line[len(prefix) :].strip().strip('"')
    return default


def parse_bdf(text: str, source: str) -> BdfFont:
    """Parse the BDF fields needed to reproduce its native bitmap pixels."""

    lines = text.splitlines()
    if not lines or not lines[0].startswith("STARTFONT"):
        raise BuildError(f"{source}: not a BDF font")
    try:
        ascent = int(_property_value(lines, "FONT_ASCENT"))
        descent = int(_property_value(lines, "FONT_DESCENT"))
    except ValueError as exc:
        raise BuildError(f"{source}: missing or invalid FONT_ASCENT/FONT_DESCENT") from exc

    family = _property_value(lines, "FAMILY_NAME", "unknown")
    version = _property_value(lines, "FONT_VERSION", "unknown")
    glyphs: dict[int, Glyph] = {}
    index = 0

    while index < len(lines):
        if not lines[index].startswith("STARTCHAR"):
            index += 1
            continue
        start_line = index + 1
        index += 1
        encoding: int | None = None
        dwidth: int | None = None
        bbx: tuple[int, int, int, int] | None = None
        bitmap: list[str] = []
        in_bitmap = False

        while index < len(lines) and lines[index] != "ENDCHAR":
            line = lines[index].strip()
            if in_bitmap:
                bitmap.append(line)
            elif line.startswith("ENCODING "):
                encoding = int(line.split()[1])
            elif line.startswith("DWIDTH "):
                fields = line.split()
                dwidth = int(fields[1])
            elif line.startswith("BBX "):
                fields = line.split()
                if len(fields) != 5:
                    raise BuildError(f"{source}:{index + 1}: malformed BBX")
                bbx = tuple(int(field) for field in fields[1:])  # type: ignore[assignment]
            elif line == "BITMAP":
                in_bitmap = True
            index += 1

        if index >= len(lines):
            raise BuildError(f"{source}:{start_line}: unterminated glyph")
        index += 1

        if encoding is None or encoding < 0:
            continue
        if encoding > 0x10FFFF:
            raise BuildError(f"{source}:{start_line}: invalid Unicode codepoint {encoding}")
        if encoding in glyphs:
            raise BuildError(f"{source}:{start_line}: duplicate U+{encoding:04X}")
        if dwidth is None or bbx is None:
            raise BuildError(f"{source}:{start_line}: glyph U+{encoding:04X} lacks metrics")

        width, height, x_offset, y_offset = bbx
        if width < 0 or height < 0:
            raise BuildError(f"{source}:{start_line}: negative BBX for U+{encoding:04X}")
        if len(bitmap) != height:
            raise BuildError(
                f"{source}:{start_line}: U+{encoding:04X} has {len(bitmap)} bitmap "
                f"rows, expected {height}"
            )
        expected_nibbles = ((width + 7) // 8) * 2
        rows: list[int] = []
        row_bits: list[int] = []
        for row in bitmap:
            if row and not re.fullmatch(r"[0-9A-Fa-f]+", row):
                raise BuildError(f"{source}:{start_line}: invalid bitmap for U+{encoding:04X}")
            if len(row) < expected_nibbles:
                raise BuildError(f"{source}:{start_line}: short bitmap row for U+{encoding:04X}")
            rows.append(int(row, 16) if row else 0)
            row_bits.append(len(row) * 4)

        glyphs[encoding] = Glyph(
            codepoint=encoding,
            dwidth=dwidth,
            width=width,
            height=height,
            x_offset=x_offset,
            y_offset=y_offset,
            rows=tuple(rows),
            row_bits=tuple(row_bits),
        )

    if not glyphs:
        raise BuildError(f"{source}: BDF contains no encoded glyphs")
    return BdfFont(family, version, ascent, descent, glyphs)


def load_bdf(mod_dir: Path, explicit_bdf: Path | None) -> tuple[BdfFont, str]:
    path = (
        explicit_bdf.expanduser().resolve()
        if explicit_bdf is not None
        else (mod_dir / "assets" / "font" / "quan.bdf").resolve()
    )
    if not path.is_file():
        if explicit_bdf is None:
            raise BuildError(
                "default BDF file does not exist: "
                f"{path}\nplace quan.bdf at assets/font/quan.bdf "
                "or pass --bdf <path>"
            )
        raise BuildError(f"BDF file does not exist: {path}")
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        text = path.read_text(encoding="ascii")
    return parse_bdf(text, str(path)), str(path)


def glyph_pixels(glyph: Glyph, font: BdfFont) -> tuple[tuple[int, int], ...]:
    """Place a BDF glyph on the font's native 8x8 baseline without scaling."""

    if glyph.dwidth > CELL_SIZE:
        raise BuildError(
            f"U+{glyph.codepoint:04X} {chr(glyph.codepoint)!r} has advance "
            f"{glyph.dwidth}, wider than an {CELL_SIZE}px cell"
        )
    top = font.ascent - (glyph.y_offset + glyph.height)
    left = glyph.x_offset
    if (
        left < 0
        or top < 0
        or left + glyph.width > CELL_SIZE
        or top + glyph.height > CELL_SIZE
    ):
        raise BuildError(
            f"U+{glyph.codepoint:04X} {chr(glyph.codepoint)!r} has BBX "
            f"{glyph.width}x{glyph.height}{glyph.x_offset:+d}{glyph.y_offset:+d}; "
            f"it does not fit the font's {CELL_SIZE}x{CELL_SIZE} cell at "
            f"ascent {font.ascent} without cropping or scaling"
        )

    pixels: list[tuple[int, int]] = []
    for row_index, (row, bit_count) in enumerate(zip(glyph.rows, glyph.row_bits)):
        for column in range(glyph.width):
            if row & (1 << (bit_count - 1 - column)):
                pixels.append((left + column, top + row_index))
    return tuple(pixels)


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    checksum = binascii.crc32(kind)
    checksum = binascii.crc32(payload, checksum) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)


def png_rgba(width: int, height: int, pixels: bytearray) -> bytes:
    if len(pixels) != width * height * 4:
        raise AssertionError("RGBA buffer has the wrong size")
    scanlines = bytearray()
    stride = width * 4
    for y in range(height):
        scanlines.append(0)  # PNG filter type: None
        start = y * stride
        scanlines.extend(pixels[start : start + stride])
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", header)
        + _png_chunk(b"IDAT", zlib.compress(bytes(scanlines), level=9))
        + _png_chunk(b"IEND", b"")
    )


def build_pages(codepoints: list[int], font: BdfFont) -> list[bytes]:
    pages: list[bytes] = []
    for page_start in range(0, len(codepoints), GLYPHS_PER_PAGE):
        rgba = bytearray(PAGE_SIZE * PAGE_SIZE * 4)
        page_codepoints = codepoints[page_start : page_start + GLYPHS_PER_PAGE]
        for slot, codepoint in enumerate(page_codepoints):
            glyph = font.glyphs[codepoint]
            cell_x = (slot % PAGE_COLUMNS) * CELL_SIZE
            cell_y = (slot // PAGE_COLUMNS) * CELL_SIZE
            for x, y in glyph_pixels(glyph, font):
                offset = ((cell_y + y) * PAGE_SIZE + cell_x + x) * 4
                rgba[offset : offset + 4] = b"\x00\x00\x00\xFF"
        pages.append(png_rgba(PAGE_SIZE, PAGE_SIZE, rgba))
    return pages


def lua_quote(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


def font_lua(page_count: int, image_prefix: str) -> bytes:
    lines = [
        "-- Generated by tools/build_zh_cn_font.py; do not edit by hand.",
        "-- QuanPixel glyphs are copied at native resolution into 8x8 cells.",
        "return {",
    ]
    for page in range(page_count):
        name = f"zh_cn_{page:03d}"
        lines.extend(
            [
                f'  ["{name}"] = {{',
                f'    image = "{image_prefix}/{name}.png",',
                f"    base = 0x{BASE_CODE + page * GLYPHS_PER_PAGE:X},",
                f"    glyphsPerRow = {PAGE_COLUMNS},",
                f"    advance = {CELL_SIZE},",
                "  },",
            ]
        )
    lines.extend(["}", ""])
    return "\n".join(lines).encode("utf-8")


def charmap_lua(codepoints: list[int]) -> bytes:
    lines = [
        "-- Generated by tools/build_zh_cn_font.py; do not edit by hand.",
        "-- ASCII is intentionally absent so the vanilla font keeps drawing it.",
        "return {",
    ]
    for index, codepoint in enumerate(codepoints):
        char = chr(codepoint)
        lines.append(
            f"  [{lua_quote(char)}] = 0x{BASE_CODE + index:X}, -- U+{codepoint:04X}"
        )
    lines.extend(["}", ""])
    return "\n".join(lines).encode("utf-8")


def expected_outputs(
    mod_dir: Path, repo_root: Path, codepoints: list[int], pages: list[bytes]
) -> dict[Path, bytes]:
    lang_dir = mod_dir / "lang"
    page_dir = lang_dir / "font"
    try:
        mod_relative = mod_dir.resolve().relative_to(repo_root.resolve()).as_posix()
        if not mod_relative.startswith("mods/"):
            mod_relative = f"mods/{mod_dir.name}"
    except ValueError:
        # Useful for isolated smoke tests. A real installed mod normally lives
        # at mods/<manifest-id>, which is the loader path emitted by default.
        mod_relative = f"mods/{mod_dir.name}"
    image_prefix = f"{mod_relative}/lang/font"

    outputs = {
        lang_dir / "font.lua": font_lua(len(pages), image_prefix),
        lang_dir / "charmap.lua": charmap_lua(codepoints),
    }
    for index, png in enumerate(pages):
        outputs[page_dir / f"zh_cn_{index:03d}.png"] = png
    return outputs


def generated_page_paths(page_dir: Path) -> set[Path]:
    if not page_dir.is_dir():
        return set()
    return {path for path in page_dir.iterdir() if PAGE_NAME_RE.fullmatch(path.name)}


def check_outputs(outputs: dict[Path, bytes], page_dir: Path) -> list[str]:
    problems: list[str] = []
    expected_pages = {path for path in outputs if path.suffix == ".png"}
    for path, expected in outputs.items():
        if not path.is_file():
            problems.append(f"missing {path}")
        elif path.read_bytes() != expected:
            problems.append(f"out of date {path}")
    for stale in sorted(generated_page_paths(page_dir) - expected_pages):
        problems.append(f"stale {stale}")
    return problems


def write_outputs(outputs: dict[Path, bytes], page_dir: Path) -> list[Path]:
    changed: list[Path] = []
    expected_pages = {path for path in outputs if path.suffix == ".png"}
    for path, content in outputs.items():
        if path.is_file() and path.read_bytes() == content:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        changed.append(path)
    for stale in sorted(generated_page_paths(page_dir) - expected_pages):
        stale.unlink()
        changed.append(stale)
    return changed


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--bdf",
        type=Path,
        help="read this BDF instead of <mod>/assets/font/quan.bdf",
    )
    parser.add_argument(
        "--mod-dir",
        type=Path,
        help="translation mod directory (default: mods/zh_cn)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify deterministic outputs without writing files",
    )
    return parser.parse_args(argv)


def run(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    script_path = Path(__file__).resolve()
    bundled_mod_dir = script_path.parent.parent
    if not (bundled_mod_dir / "manifest.json").is_file():
        raise BuildError(
            "the bundled builder must remain under <mod>/tools/"
        )
    if bundled_mod_dir.parent.name == "mods":
        repo_root = bundled_mod_dir.parent.parent
    else:
        # Also support a development ZIP extracted outside a source checkout.
        # In that layout callers normally pass --bdf explicitly.
        repo_root = bundled_mod_dir.parent
    mod_dir = (args.mod_dir or bundled_mod_dir).resolve()
    lang_dir = mod_dir / "lang"

    codepoints, usages = required_characters(lang_dir)
    font, font_source = load_bdf(mod_dir, args.bdf)

    missing = [codepoint for codepoint in codepoints if codepoint not in font.glyphs]
    if missing:
        lines = [
            f"{font.family} {font.version} is missing {len(missing)} required glyph(s):"
        ]
        for codepoint in missing:
            locations = ", ".join(usages[codepoint][:4])
            if len(usages[codepoint]) > 4:
                locations += ", ..."
            lines.append(f"  U+{codepoint:04X} {chr(codepoint)!r} ({locations})")
        raise BuildError("\n".join(lines))

    # Validate every glyph's native metrics before allocating/writing pages.
    for codepoint in codepoints:
        try:
            glyph_pixels(font.glyphs[codepoint], font)
        except BuildError as exc:
            locations = ", ".join(usages[codepoint][:4])
            raise BuildError(f"{exc}; used by {locations}") from exc

    pages = build_pages(codepoints, font)
    outputs = expected_outputs(mod_dir, repo_root, codepoints, pages)
    page_dir = lang_dir / "font"

    if args.check:
        problems = check_outputs(outputs, page_dir)
        if problems:
            print("zh_cn font outputs are not reproducible/current:", file=sys.stderr)
            for problem in problems:
                print(f"  {problem}", file=sys.stderr)
            print("run tools/build_zh_cn_font.py to rebuild them", file=sys.stderr)
            return 1
        print(
            f"zh_cn font check passed: {len(codepoints)} glyphs, "
            f"{len(pages)} page(s), {font.family} {font.version}"
        )
        return 0

    changed = write_outputs(outputs, page_dir)
    print(
        f"built {len(codepoints)} zh_cn glyphs in {len(pages)} page(s) "
        f"from {font.family} {font.version} ({font_source})"
    )
    if changed:
        print(f"updated {len(changed)} file(s)")
    else:
        print("outputs were already current")
    return 0


def main() -> int:
    _configure_stdio()
    try:
        return run()
    except (BuildError, OSError) as exc:
        print(f"build_zh_cn_font.py: error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
