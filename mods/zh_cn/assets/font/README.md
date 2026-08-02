The Simplified-Chinese atlas is generated under `lang/font/` from
`assets/font/quan.bdf`. Its native bitmap pixels are copied into 8x8 cells
without scaling or antialiasing. The builder no longer searches for a ZIP.

From this mod directory, rebuild and verify it with:

```text
python .\tools\build_zh_cn_font.py
python .\tools\build_zh_cn_font.py --check
```

Pass `--bdf <path>` to use another 8x8 Unicode BDF. See `FONT_WORKFLOW.md` for
the full PowerShell generation, validation, and mod-packaging workflow.

`lang/font.lua` declares the generated pages and `lang/charmap.lua` maps
UTF-8 characters to their glyph codes. QuanPixel is the default input. The
Fusion Pixel 8px monospaced BDF is the compatible packaged alternative; its
proportional sibling has a 12-pixel vertical bounding box / 9-pixel ascent and
cannot be placed losslessly in this engine's fixed 8x8 cell, so `.modkitignore`
keeps it out of the mod ZIP. Copyright notices and the SIL OFL 1.1 text for both
packaged font families are included under `LICENSES/`.
