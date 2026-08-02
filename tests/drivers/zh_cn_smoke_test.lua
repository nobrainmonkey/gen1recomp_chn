-- Visual/runtime smoke test for the Simplified-Chinese translation mod.
-- Runs in an isolated POKEPORT_IDENTITY and exits after writing five shots.

return function(game)
  local shotDir = assert(os.getenv("SHOT_DIR"), "SHOT_DIR is required")
  local logPath = shotDir .. "/smoke.log"
  os.remove(logPath)
  for _, name in ipairs({
    "01_pallet_town_3d.png",
    "02_pallet_town_dialogue.png",
    "03_dramatic_shape_options.png",
    "03_dramatic_shape_full.png",
    "03_oak_opening_dialogue.png",
    "04_dramatic_shape_full.png",
    "04_dramatic_shape_options_expanded.png",
    "05_dramatic_shape_options_expanded.png",
  }) do
    os.remove(shotDir .. "/" .. name)
  end

  local function mark(message)
    local file = assert(io.open(logPath, "ab"))
    file:write(tostring(message), "\n")
    file:close()
  end

  mark("driver started")

  local function wait(frames)
    for _ = 1, frames do coroutine.yield() end
  end

  local function capture(name)
    local path = shotDir .. "/" .. name
    os.remove(path)
    game.capturePath = path
    for _ = 1, 300 do
      wait(1)
      local file = io.open(path, "rb")
      if file then
        file:close()
        print("[zh_cn smoke] captured " .. path)
        return
      end
    end
    error("screenshot was not written: " .. path)
  end

  local function loaded(id)
    for _, manifest in ipairs((game.modStatus and game.modStatus.loaded) or {}) do
      if manifest.id == id then return true end
    end
    return false
  end

  local loadedIds = {}
  for _, manifest in ipairs((game.modStatus and game.modStatus.loaded) or {}) do
    loadedIds[#loadedIds + 1] = manifest.id .. ":" .. tostring(manifest.state)
  end
  mark("loaded mods: " .. table.concat(loadedIds, ", "))
  for _, manifest in ipairs((game.modStatus and game.modStatus.available) or {}) do
    mark("available " .. tostring(manifest.id) .. ": state=" ..
         tostring(manifest.state) .. ", enabled=" .. tostring(manifest.enabled) ..
         ", error=" .. tostring(manifest.error))
  end
  for _, err in ipairs((game.modStatus and game.modStatus.errors) or {}) do
    mark("loader error: " .. tostring(err))
  end
  assert(loaded("zh_cn"), "zh_cn did not load")
  assert(loaded("DRAMATIC_SHAPE"), "DRAMATIC_SHAPE did not load")
  assert(#((game.modStatus and game.modStatus.errors) or {}) == 0,
         "the mod loader reported an error")
  mark("PIKACHU=" .. tostring(game.data.pokemon.PIKACHU.name))
  assert(game.data.pokemon.PIKACHU.name == "皮卡丘",
         "official Pikachu name was not applied")
  assert(game.data.moves.THUNDERBOLT.name == "十万伏特",
         "official Thunderbolt name was not applied")
  assert(game.data.items.POKE_BALL.name == "精灵球",
         "official Poké Ball name was not applied")
  assert(game.data.statuses.BRN.hudLabel == "灼伤",
         "battle HUD status label was not applied")
  assert(game.data.type_chart.types.BIRD == nil,
         "unused BIRD type was accidentally registered")
  assert(game.data.field.boot.namePresets.player[1] == "赤红" and
         game.data.field.boot.namePresets.rival[1] == "青绿",
         "Chinese name presets were not applied")
  local Strings = require("src.core.Strings")
  assert(Strings("_OakSpeechText2A") == "_OakSpeechText2A",
         "Oak's Nidorino demo dialogue key was translated instead of its text")
  local function assertTranslatedText(id, needle)
    local value = game.data.text[id]
    assert(type(value) == "string" and value:find(needle, 1, true),
           id .. " was not translated as expected")
  end

  assertTranslatedText("_PalletTownSignText", "真新镇")
  assertTranslatedText("_OakSpeechText1", "大木")
  assertTranslatedText("_OakSpeechText2A", "宝可梦")
  assertTranslatedText("_OakSpeechText2B", "职业")
  assertTranslatedText("_OakSpeechText3", "传说")
  assertTranslatedText("_IntroducePlayerText", "名字")
  assertTranslatedText("_IntroduceRivalText", "孙子")
  assert(not game.data.text._OakSpeechText1:find("OAK", 1, true),
         "Professor Oak's opening speech still contains English")

  -- Touch late-game and end-of-catalogue entries as a regression check that
  -- this is the complete dialogue catalogue, not the earlier partial build.
  assertTranslatedText("_ViridianGymGiovanniPreBattleText", "火箭队")
  assertTranslatedText("_ZubatDexEntry", "超声波")

  while game.stack:top() do game.stack:pop() end
  local Overworld = require("src.world.OverworldController")
  game.stack:push(Overworld, "PALLET_TOWN", 5, 6, "down")
  mark("entered PALLET_TOWN")

  -- Give Dramatic Shape time to build and upload the first nearby meshes.
  wait(240)
  local Pipelines = require("src.render.Pipelines")
  local pipeline = Pipelines.worldPipeline()
  mark("world pipeline=" .. tostring(pipeline))
  assert(pipeline == "voxel", "Dramatic Shape voxel pipeline is unavailable")
  capture("01_pallet_town_3d.png")

  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, game.data.text._PalletTownSignText))
  wait(90)
  capture("02_pallet_town_dialogue.png")
  game.stack:pop()

  game.stack:push(TextBox.new(game, game.data.text._OakSpeechText1))
  wait(90)
  capture("03_oak_opening_dialogue.png")
  game.stack:pop()

  local OptionsMenu = require("src.ui.OptionsMenu")
  local wanted = {
    ["zoom"] = "缩放",
    ["pipeline:voxel"] = "立体世界",
    ["pipeline:tiltshift"] = "移轴景深",
    ["DRAMATIC_SHAPE:grid"] = "体素网格",
    ["DRAMATIC_SHAPE:curve"] = "世界曲面",
    ["DRAMATIC_SHAPE:water"] = "水面反射",
    ["DRAMATIC_SHAPE:battles"] = "立体对战",
    ["DRAMATIC_SHAPE:battleBack"] = "背面图像",
    ["DRAMATIC_SHAPE:daytime"] = "昼夜时间",
  }

  local function rowsById(menu)
    local rows = {}
    for _, row in ipairs(menu.rows) do rows[row.id] = row end
    return rows
  end

  local function checkRow(rows, id)
    local row = assert(rows[id], id .. " option row is missing")
    mark(id .. "=" .. tostring(row.label) .. "/" ..
         tostring(row.value and row.value(game)))
    assert(row.label == wanted[id], id .. " label was not translated")
    return row
  end

  -- FULL intentionally hides the knobs it owns, but keeps both battle rows.
  local menu = OptionsMenu.new(game)
  local fullRows = rowsById(menu)
  local voxel = checkRow(fullRows, "pipeline:voxel")
  local zoom = checkRow(fullRows, "zoom")
  local battles = checkRow(fullRows, "DRAMATIC_SHAPE:battles")
  local battleBack = checkRow(fullRows, "DRAMATIC_SHAPE:battleBack")
  assert(voxel.value(game) == "完整", "FULL value was not translated")
  assert(zoom.value(game) == "适应", "FIT zoom value was not translated")
  assert(battles.value(game) == "开启", "3D battle value was not translated")
  assert(battleBack.value(game) == "关闭", "back-sprite value was not translated")
  for _, id in ipairs({ "pipeline:tiltshift", "DRAMATIC_SHAPE:grid",
                         "DRAMATIC_SHAPE:curve", "DRAMATIC_SHAPE:water",
                         "DRAMATIC_SHAPE:daytime" }) do
    assert(fullRows[id] == nil, id .. " should be hidden by FULL")
  end
  for index, row in ipairs(menu.rows) do
    if row.id == "pipeline:voxel" then
      menu.index, menu.scroll = index, index - 1
      break
    end
  end
  game.stack:push(menu)
  wait(12)
  capture("04_dramatic_shape_full.png")
  game.stack:pop()

  -- Leave the preset and verify every dynamic 1.4.0 row is still translated.
  Pipelines.setLevel("voxel", 4)
  Pipelines.syncOptions(game.save.options)
  wait(4)
  local expanded = OptionsMenu.new(game)
  local expandedRows = rowsById(expanded)
  for id in pairs(wanted) do checkRow(expandedRows, id) end
  for index, row in ipairs(expanded.rows) do
    if row.id == "pipeline:voxel" then
      expanded.index, expanded.scroll = index, index - 1
      break
    end
  end
  game.stack:push(expanded)
  wait(12)
  capture("05_dramatic_shape_options_expanded.png")

  mark("PASS")
  print("[zh_cn smoke] PASS: translation, font, and Dramatic Shape loaded")
end
