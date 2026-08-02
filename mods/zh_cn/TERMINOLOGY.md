# Simplified-Chinese terminology

This mod targets Mainland Simplified Chinese only. It does not contain a
Traditional-Chinese mode or automatic character conversion.

## Authority and scope

- All 151 Pokémon names are copied exactly from the user's
  `pokemon_names.txt`, keyed by National Pokédex number and then mapped to the
  engine's symbolic species IDs.
- Move, item, type, badge, trainer-class, character, and Kanto place names use
  the current official Simplified-Chinese game terminology where it exists.
- Pokémon Red, Blue, and Yellow never received official Mainland
  Simplified-Chinese game scripts. Narrative sentences in `lang/dialogue.lua`
  and engine-specific text in `lang/strings.lua` are therefore new
  translations, while named terms in them follow the official glossary.

## Core glossary

| English concept | Simplified Chinese |
|---|---|
| Pokémon | 宝可梦 |
| Pokédex | 宝可梦图鉴 |
| Poké Ball | 精灵球 |
| move | 招式 |
| Pokémon Trainer | 宝可梦训练家 |
| Pokémon Center | 宝可梦中心 |
| Pokémon Mart | 友好商店 |
| Gym / Gym Leader | 道馆 / 道馆馆主 |
| Professor Oak | 大木博士 |
| Pallet Town | 真新镇 |
| Viridian City / Forest | 常青市 / 常青森林 |
| Pewter City | 深灰市 |

## Reference datasets

- User-supplied official species-name table: `pokemon_names.txt` (151/151).
- Pokémon China official site: <https://www.pokemon.cn/>
- Current Simplified-Chinese move and item terminology:
  <https://wiki.52poke.com/wiki/招式列表（第一世代）> and
  <https://wiki.52poke.com/wiki/道具列表>
- Kanto badge names and trainer-class terminology:
  <https://wiki.52poke.com/wiki/徽章> and
  <https://wiki.52poke.com/wiki/训练家类型列表（在其他语言中）>
- Machine-readable cross-check for current `zh-Hans` names:
  <https://github.com/PokeAPI/pokeapi/tree/master/data/v2/csv>

The source links are working references rather than permission to redistribute
any original game script. The repository and release package contain only the
new translations, supporting code, and licensed font assets. Locally extracted
English ROM worksheets remain outside both.
