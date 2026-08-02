# Translating into 简体中文

Everything the player can read is one of two kinds of string, and they live
in different places for a reason.

| lang/ file | What it is | Key |
|---|---|---|
| `dialogue.lua` | Yellow text plus lines shared by all versions | the original label, e.g. `_PalletTownText1` |
| `dialogue_rb.lua` | Red/Blue-only lines and same-ID wording overrides | the same original label |
| `strings.lua` | Text the engine itself writes: battle messages, menus, link play | the English source string |
| `species_names.lua` `move_names.lua` `item_names.lua` `trainer_names.lua` | Names | the vanilla id |
| `type_names.lua` `status_labels.lua` | Types and `PSN`, `BRN`, ... HUD labels | the engine id |
| `font.lua` `charmap.lua` | Your glyph sheet and what draws what | see below |
| `naming.lua` | The letter grid for entering names | - |

Fill in a value and it takes effect. Leave it `""` and that string stays in
English, so the game is playable at every point along the way.

## Where the English is

The catalogs hold keys and *your* text, never the original English. The
English lives next door, in a locally generated and ignored worksheet
directory such as `zh_cn-worksheet/`, one tab-separated file per catalog. For
example, a fictional row could look like this:

```
"_ExampleText"	"Locally extracted reference text with {PLACEHOLDER}."
```

That directory is deliberately outside the mod and must also be excluded from
the public repository. Extracted script text and the vanilla names are ROM
content, and `modkit pack` zips everything under the mod directory, so a
worksheet kept inside would end up in your release whatever a `.gitignore`
said. Keep it beside the mod, never in it.

`lang/strings.lua` is the exception: those sources are the engine's own Lua
rather than anything out of the ROM, so there the key *is* the English and
you can translate straight from it.

## Start with the font, not the text

The engine draws from **glyph pages**: an image of 8x8 cells plus a charmap
saying which byte sequence draws which cell. The vanilla pages sit at `$60`
and `$80`. Anything from `0x100` up is free, so a new alphabet is added
rather than swapped in:

```lua
-- lang/font.lua
return {
  ["zh_cn_000"] = {
    image = "mods/zh_cn/lang/font/zh_cn_000.png",
    base = 0x100,        -- first code this page owns
    glyphsPerRow = 16,
    advance = 8,
  },
}
```

```lua
-- lang/charmap.lua: sequence -> code, in the same order as the sheet
return {
  ["宝"] = 0x100,
  ["可"] = 0x101,
}
```

Each generated page is a transparent PNG under `lang/font/`, with opaque black
pixels in 16 glyphs per row and an 8x8 cell for every glyph. Codes run left to
right, top to bottom from `base`; additional pages advance the base by `0x100`.
The bundled builder regenerates every page, `font.lua`, and `charmap.lua`
together, so these outputs should not be edited by hand.

The renderer matches sequences **longest first**, so a multi-byte character and
a manually authored multi-character ligature can coexist. The bundled builder
normally emits one Unicode character per glyph:

```lua
["\u{3042}"] = 0x120,   -- one 3-byte character, one glyph
["ch"] = 0x121,          -- two ASCII letters, one glyph
```

## Line length is counted in glyphs

The dialogue box fits 18 glyphs a line, not 18 bytes. A 3-byte character
costs one column, and the engine will never cut a character in half. Your
own `\n` line breaks are respected exactly as written, so break lines where
they read best rather than where they fit English.

If your glyphs are not 8px wide, set `advance` on the page and the box
re-measures.

## Format directives must survive

Some sources carry `%s` or `%d`:

```lua
["Wild %s\nappeared!"] = "...",
```

Keep every directive, in a count that matches. Word order is yours to
change; the engine substitutes in the order the directives appear, so if
your language needs the name last, write the sentence with the `%s` last.
A translation whose directive count does not match the English is refused
at runtime and the English is drawn instead, with a line in the log saying
so - it will not crash a battle.

## Checking your work

The public checker contains no English game script. Give it the generated
`text.lua` files from ROMs you legally own. From this translation repository's
root, a three-version check looks like:

```powershell
py -3 .\tools\check_zh_cn_dialogue.py `
  --source 'red=<local-red-text.lua>' `
  --source 'blue=<local-blue-text.lua>' `
  --source 'yellow=<local-yellow-text.lua>'
```

The checker applies `dialogue_rb.lua` only to Red/Blue, then verifies coverage,
placeholders, format tokens, page breaks, and the 18-glyph dialogue width. The
paths above are placeholders: do not write a personal absolute path into a
committed document or script.

For engine-side validation, run the following from your own Gen1Recomp source
checkout after making its imported data available:

```sh
python3 tools/modkit.py validate zh_cn --base imported
POKEPORT_DEV=1 scripts/run.sh                          # F5 hot-reloads lang/
```

After pulling a new engine version, regenerate local Red, Blue, and Yellow
sources and compare all three. Do not run a one-version catalogue refresh over
the combined files without first making a backup: same-ID dialogue can have
different meanings between Red/Blue and Yellow.
