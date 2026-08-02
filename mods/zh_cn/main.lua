-- zh_cn: Mainland Simplified-Chinese translation for Pokemon Red, Blue,
-- and Yellow.
-- Catalogue values that are empty or added by a future game update fall back
-- to the base game instead of replacing text with a blank string.
return function(mod)
  -- mod:read is the supported way into your own directory; the catalogs are
  -- plain Lua tables, so read and run them rather than require()ing them.
  local function catalog(name)
    local rel = "lang/" .. name .. ".lua"
    local body = mod:read(rel)
    if not body then return {} end
    local chunk, err = loadstring(body, rel)
    if not chunk then
      mod.log:warn("%s has a syntax error: %s", rel, tostring(err))
      return {}
    end
    local ok, table_ = pcall(chunk)
    if not ok or type(table_) ~= "table" then
      mod.log:warn("%s did not return a table: %s", rel, tostring(table_))
      return {}
    end
    return table_
  end

  -- An empty value means "use the base-game value", never "translate to blank".
  local function each(name, apply)
    local n = 0
    for key, value in pairs(catalog(name)) do
      if type(value) == "string" and value ~= "" then
        -- A callback may return false when a version-specific entry is not
        -- present in this generation's verified ROM catalogue.
        if apply(key, value) ~= false then n = n + 1 end
      end
    end
    return n
  end

  -- ---- glyphs -------------------------------------------------------
  -- Register the sheet BEFORE anything asks for a glyph on it.  base is
  -- the first code the page owns; 0x100 and up is free space above the
  -- vanilla pages, so a new alphabet never collides with them.
  for id, page in pairs(catalog("font")) do
    mod.content.font:register(id, page)
  end
  -- charmap: which byte sequence draws which code
  for seq, code in pairs(catalog("charmap")) do
    mod.content.font:register("charmap:" .. seq, { seq = seq, code = code })
  end

  -- ---- text ---------------------------------------------------------
  local counts = {}
  -- Snapshot the pristine R/B id set before the shared catalogue writes any
  -- overrides.  The public content facade exposes get(), not Registry:has().
  -- This also keeps an obsolete version-only id out of a future cache: after
  -- the shared pass, get() alone could no longer distinguish a base id from
  -- one the shared catalogue just introduced.
  local gameVersion = require("src.core.GameVersion").get()
  local rbBaseIds
  if gameVersion == "red" or gameVersion == "blue" then
    rbBaseIds = {}
    for id, value in pairs(catalog("dialogue_rb")) do
      if type(value) == "string" and value ~= ""
          and mod.content.text:get(id) ~= nil then
        rbBaseIds[id] = true
      end
    end
  end
  counts.dialogue = each("dialogue", function(id, value)
    mod.content.text:override(id, value)
  end)
  -- Red and Blue share the same ROM text, but some of their dialogue ids
  -- either do not exist in Yellow or have different wording under the same
  -- id. GameVersion is selected and its cache mounted before Data and mods
  -- load, so it remains stable for this process. Apply the compact R/B
  -- catalogue second so those version-specific values win.
  if rbBaseIds then
    counts.dialogue_rb = each("dialogue_rb", function(id, value)
      -- Catalogue ids changed across Gen1Recomp data generations.  Do not
      -- manufacture an obsolete id when a newer verified cache no longer
      -- has it; common and currently referenced ids are still overridden.
      if not rbBaseIds[id] then return false end
      mod.content.text:override(id, value)
      return true
    end)
  end
  counts.strings = each("strings", function(source, value)
    mod.content.strings:override(source, value)
  end)
  counts.species = each("species_names", function(id, value)
    mod.content.pokemon:patch(id, { name = value })
  end)
  counts.moves = each("move_names", function(id, value)
    mod.content.moves:patch(id, { name = value })
  end)
  counts.items = each("item_names", function(id, value)
    mod.content.items:patch(id, { name = value })
  end)
  counts.trainers = each("trainer_names", function(id, value)
    mod.content.trainers:patch(id, { name = value })
  end)
  counts.types = each("type_names", function(id, value)
    mod.content.type_chart:patch(id, { name = value })
  end)
  counts.statuses = each("status_labels", function(id, value)
    mod.content.statuses:patch(id, { label = value, hudLabel = value })
  end)

  -- Put the official Chinese character names first while preserving the
  -- original English presets after them. Custom keyboard entry stays Latin.
  mod.content.field:patch("boot", {
    namePresets = {
      player = { __prepend = { "赤红", "小智" } },
      rival = { __prepend = { "青绿", "小茂" } },
    },
  })

  -- ---- name entry ---------------------------------------------------
  -- The naming screen's letter grid.  Leave lang/naming.lua returning nil
  -- to keep the English alphabet.
  local grid = catalog("naming")
  if grid.upper then
    mod.hooks:wrap("ui.naming.grid", function(next, base, ctx)
      local inherited = next(base, ctx)
      local want = ctx.lower and grid.lower or grid.upper
      return want or inherited
    end)
  end

  -- Dramatic Shape owns two render-pipeline rows and six settings rows whose
  -- labels are intentionally supplied by that mod rather than the engine's
  -- string catalog.  Translate them by stable row id when both mods are on.
  -- A high hook priority makes this the outer decorator regardless of load
  -- order, while next() still lets Dramatic Shape group and hide its rows.
  local optionLabels = {
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
  local optionValues = {
    OFF = "关闭",
    ON = "开启",
    FULL = "完整",
    SKY = "天空",
    SYNC = "同步",
    DAY = "白天",
    NIGHT = "夜晚",
    DUSK = "黄昏",
    DAWN = "黎明",
    CYCLE = "循环",
    FIT = "适应",
  }
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    for _, row in ipairs(out) do
      if type(row) == "table" and optionLabels[row.id] then
        row.label = optionLabels[row.id]
        if type(row.value) == "function" then
          local value = row.value
          row.value = function(...)
            local raw = value(...)
            local out = type(raw) == "string" and raw:match("^OUT(%d+)$")
            if out then return "缩小" .. out end
            local inward = type(raw) == "string" and raw:match("^IN(%d+)$")
            if inward then return "放大" .. inward end
            return optionValues[raw] or raw
          end
        end
      end
    end
    return out
  end, 1000)

  -- Gen1Recomp 0.1.56 passes the options footer to OptionRows as the raw
  -- literal "CANCEL", so it never reaches the normal string catalogue.  Keep
  -- the workaround deliberately narrow: only translate that exact footer and
  -- delegate every other draw unchanged.  The engine_internals permission in
  -- the manifest makes this small compatibility patch explicit to players.
  do
    local ok, OptionRows = pcall(require, "src.ui.OptionRows")
    if ok and type(OptionRows) == "table"
        and type(OptionRows.draw) == "function"
        and not OptionRows.__zh_cn_cancel_footer then
      local draw = OptionRows.draw
      OptionRows.draw = function(game, rows, index, scroll, bottomLabel,
                                 bottomRow)
        if bottomLabel == "CANCEL" then bottomLabel = "取消" end
        return draw(game, rows, index, scroll, bottomLabel, bottomRow)
      end
      OptionRows.__zh_cn_cancel_footer = true
    elseif not ok then
      mod.log:warn("无法加载选项页取消按钮的翻译兼容层: %s",
                   tostring(OptionRows))
    end
  end

  mod.events:on("game.ready", function()
    local total = 0
    for _, n in pairs(counts) do total = total + n end
    mod.log:info("简体中文: %d strings translated", total)
  end)
end
