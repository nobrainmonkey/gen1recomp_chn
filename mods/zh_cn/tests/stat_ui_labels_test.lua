-- Headless regression for stat/status labels that Gen1Recomp 0.1.56 does
-- not route through its normal localization registries.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local OptionRows = require("src.ui.OptionRows")
local Version = require("src.core.Version")
local GameVersion = require("src.core.GameVersion")
local sdk = require("tests.modkit.sdk")
local disk = require("tests.fs_io").new(".")

-- main.lua installs process-wide compatibility wrappers. Save every touched
-- field so this standalone test also behaves well if a larger runner dofiles
-- it in a shared Lua process.
local before = {
  fontDraw = Font.draw,
  fontStatLabels = Font.__zh_cn_stat_labels,
  fontStatusLabels = Font.__zh_cn_status_labels,
  fontTranslate = Font.__zh_cn_translate_ui_label,
  fontCompat = Font.__zh_cn_ui_label_compat,
  stringsGet = Strings.get,
  stringsLabels = Strings.__zh_cn_stat_argument_labels,
  stringsPositions = Strings.__zh_cn_stat_argument_positions,
  stringsCompat = Strings.__zh_cn_stat_argument_compat,
  optionDraw = OptionRows.draw,
  optionCompat = OptionRows.__zh_cn_cancel_footer,
  engineVersion = Version.engine,
  gameVersion = GameVersion.get(),
}

-- Working-tree tests advertise 0.0.0-dev; exercise the minimum supported
-- release because the production payload is stamped during packaging.
Version.engine = "0.1.56"
local testVersion = os.getenv("ZH_CN_TEST_VERSION") or "red"
GameVersion.set(testVersion)
-- Experimental mods default off when no options entry exists. Supply an
-- isolated read-only options view that enables only this mod.
local fs = {
  root = disk.root,
  read = function(path)
    if path == "options.lua" then
      return "return { mods = { zh_cn = true } }\n"
    end
    return disk.read(path)
  end,
  load = function(path)
    if path == "options.lua" then
      return assert(loadstring("return { mods = { zh_cn = true } }"))
    end
    return disk.load(path)
  end,
  getInfo = function(path)
    if path == "options.lua" then return { type = "file" } end
    return disk.getInfo(path)
  end,
  getDirectoryItems = function(path)
    if path == "mods" then return { "zh_cn" } end
    return disk.getDirectoryItems(path)
  end,
}
local run = sdk.loadMod("mods/zh_cn", { fs = fs })
assert(#run.errors == 0, table.concat(run.errors, "\n"))
assert(run.mod and run.mod.state == "loaded",
       "zh_cn did not load (state=" .. tostring(run.mod and run.mod.state)
       .. ", error=" .. tostring(run.mod and run.mod.error) .. ")")
Strings.load(run.data)

local expectedStats = {
  ATTACK = "攻击",
  DEFENSE = "防御",
  SPEED = "速度",
  SPECIAL = "特殊",
  ACCURACY = "命中率",
  EVADE = "闪避率",
}
for source, translated in pairs(expectedStats) do
  assert(Strings(source) == translated, source .. " catalogue entry")
  local line = Strings("%s's\n%s rose!", "皮卡丘", source)
  assert(line:find(translated, 1, true), source .. " format argument")
  assert(not line:find(source, 1, true), source .. " leaked into message")
end

-- Only the known stat position is rewritten. A legal nickname/trainer name
-- equal to an English stat id must remain exactly what the player chose.
local nicknameLine = Strings("%s's\n%s rose!", "ATTACK", "SPEED")
assert(nicknameLine:find("ATTACK", 1, true), "nickname ATTACK was rewritten")
assert(nicknameLine:find("速度", 1, true), "SPEED argument was not rewritten")
assert(not nicknameLine:find("攻击的", 1, true), "nickname became Chinese")

local translate = assert(Font.__zh_cn_translate_ui_label)
assert(translate("ATTACK", "@src/battle/BattleState.lua", 88, 24) == "攻击")
assert(translate("DEFENSE", "@src/battle/BattleState.lua", 88, 40) == "防御")
assert(translate("ATTACK", "@src/battle/BattleState.lua", 40, 8) == "ATTACK")
assert(translate("ATTACK", "@src/ui/SummaryMenu.lua", 72, 8) == "ATTACK")
assert(translate("BRN", "@src/ui/SummaryMenu.lua", 128, 48) == "灼伤")
assert(translate("OK", "@src/ui/SummaryMenu.lua", 128, 48) == "正常")
assert(translate("PSN", "@src/ui/PartyMenu.lua", 136, 32) == "中毒")
assert(translate(" SLP", "@src/ui/Menu.lua", 16, 16) == " 睡眠")
assert(translate(" QUIT", "@src/ui/Menu.lua", 16, 56) == " 退出")

-- Exercise the installed Font.draw wrapper too, so the debug stack level that
-- discovers the calling module cannot silently drift off by one frame.
Font.load(run.data)
local callerSeen
Font.__zh_cn_translate_ui_label = function(text, source, x, y)
  callerSeen = source
  return translate(text, source, x, y)
end
local callFromStatBox = assert(loadstring(
  "return function(Font) Font.draw('ATTACK', 88, 24) end",
  "@src/battle/BattleState.lua"))()
callFromStatBox(Font)
assert(tostring(callerSeen):gsub("\\", "/")
       :sub(-#"src/battle/BattleState.lua") == "src/battle/BattleState.lua",
       "Font wrapper did not identify BattleState as its caller")
Font.__zh_cn_translate_ui_label = translate

-- Simulate a dev hot-disable. The Font wrapper remains installed by design,
-- but must become an identity function when zh_cn leaves the merged catalog.
Strings.load({ strings = {} })
assert(translate("ATTACK", "@src/battle/BattleState.lua", 88, 24) == "ATTACK")
assert(translate("BRN", "@src/ui/SummaryMenu.lua", 128, 48) == "BRN")

run.release()
Font.draw = before.fontDraw
Font.__zh_cn_stat_labels = before.fontStatLabels
Font.__zh_cn_status_labels = before.fontStatusLabels
Font.__zh_cn_translate_ui_label = before.fontTranslate
Font.__zh_cn_ui_label_compat = before.fontCompat
Strings.get = before.stringsGet
Strings.__zh_cn_stat_argument_labels = before.stringsLabels
Strings.__zh_cn_stat_argument_positions = before.stringsPositions
Strings.__zh_cn_stat_argument_compat = before.stringsCompat
Strings.load(nil)
OptionRows.draw = before.optionDraw
OptionRows.__zh_cn_cancel_footer = before.optionCompat
Version.engine = before.engineVersion
GameVersion.set(before.gameVersion)

print("[zh_cn] PASS (" .. testVersion
      .. "): stat/status UI labels and nickname safety")
