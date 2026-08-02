-- Catalog-only regression for UI text whose source key is passed to
-- Strings dynamically, so the normal literal-source harvester cannot see it.

local strings = assert(loadfile("mods/zh_cn/lang/strings.lua"))()

local expected = {
  ["Which move?"] = "选择哪个招式？",
  ["PARTY (DEPOSIT)"] = "队伍（寄放）",
  ["FLY TO?"] = "飞往哪里？",
  ["PRIZES (COINS)"] = "奖品（代币）",
  ["<Diploma>"] = "〈奖状〉",
  ["Player"] = "玩家",
  ["GAME FREAK"] = "GAME FREAK",
  ["Congrats! This"] = "恭喜！这份",
  ["diploma certifies"] = "奖状证明",
  ["that you have"] = "你已经",
  ["completed your"] = "完成了",
  ["POKéDEX."] = "宝可梦图鉴。",
}

for source, translated in pairs(expected) do
  assert(strings[source] == translated,
    ("missing or changed UI translation for %q"):format(source))
end
