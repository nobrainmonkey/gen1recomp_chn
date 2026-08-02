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
  local statusLabels = catalog("status_labels")
  counts.statuses = each("status_labels", function(id, value)
    mod.content.statuses:patch(id, { label = value, hudLabel = value })
  end)

  -- Some hand-ported scripts fill wNameBuffer with a symbolic data id (for
  -- example "SQUIRTLE" or "EARTHBADGE").  The catalogues above localize the
  -- records, but show_text's explicit RAM substitution happens first and
  -- would otherwise print the raw id.  Use the public command hook only for
  -- the verified text rows below.  Keeping the routing narrow is important:
  -- other wNameBuffer users carry actual nicknames or arbitrary values, which
  -- must be displayed exactly as the player entered them.
  local speciesGiftTexts = {
    _OaksLabReceivedMonText = "before_give",    -- Red/Blue: player's starter
    _OaksLabRivalReceivedMonText = "explicit",  -- Red/Blue: rival's starter
    _OaksLabReceivedText = "before_give",       -- Yellow: player's Pikachu
    _GotMonText = "pending",                    -- all versions: gift Eevee
  }
  local badgeBufferTexts = {
    _Route23YouDontHaveTheBadgeYetText = true,
    _Route23OhThatIsTheBadgeText = true,
  }
  mod.hooks:wrap("script.command", function(next, ctx, command, args)
    -- Red/Blue and Yellow print the starter receipt before give_pokemon.
    -- Yellow also suppresses AskName, so give_pokemon leaves PIKACHU in this
    -- per-run context even though no later text consumes it.  Clear only the
    -- exact value paired with the immediately preceding receipt; if another
    -- mod transforms the gift to a different species, leave that value alone.
    local receipt = ctx.__zh_cn_receipt_before_give
    if command == "give_pokemon" and receipt then
      ctx.__zh_cn_receipt_before_give = nil
      local result = next()
      if type(args) == "table" and args[1] == receipt
          and ctx.pendingPokemonName == receipt then
        ctx.pendingPokemonName = nil
      end
      return result
    elseif receipt then
      -- The marker is deliberately one-command wide.
      ctx.__zh_cn_receipt_before_give = nil
    end

    local textId = type(args) == "table" and args[1]
    local giftMode = speciesGiftTexts[textId]
    local isBadge = badgeBufferTexts[textId]
    if command ~= "show_text" or type(args) ~= "table"
        or (not giftMode and not isBadge) or type(args[2]) ~= "table" then
      return next()
    end
    -- give_pokemon leaves its actual (possibly mod-transformed) species in
    -- pendingPokemonName for a following received box.  Prefer that over the
    -- script's authored fallback.  Commands.show_text consumes this field
    -- after the hook, so localize it too; otherwise it would overwrite our
    -- forwarded RAM value with the raw id again (the Celadon Eevee path).
    local pending = giftMode == "pending" and ctx.pendingPokemonName or nil
    local id = pending or args[2].RAM
    local registry = isBadge and ctx.game.data.items or ctx.game.data.pokemon
    local def = type(id) == "string" and registry[id]
    if not def or type(def.name) ~= "string" or def.name == "" then
      return next()
    end
    if ctx.pendingPokemonName then
      -- Explicit starter rows must win over a stale player-gift buffer (most
      -- importantly the rival's counter-pick).  A genuine post-give row uses
      -- the localized pending value, including a species transformed by a
      -- different mod's pokemon.before_give handler.
      ctx.pendingPokemonName = pending and def.name or nil
    end
    if giftMode == "before_give" then
      ctx.__zh_cn_receipt_before_give = id
    end

    -- Do not mutate the shared script row: another mod may inspect it later,
    -- and a language mod should only alter this one dispatch.
    local forwarded = {}
    for i, value in ipairs(args) do forwarded[i] = value end
    local substitutions = {}
    for key, value in pairs(args[2]) do substitutions[key] = value end
    substitutions.RAM = def.name
    forwarded[2] = substitutions
    return next(ctx, command, forwarded)
  end, 1000)

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

  -- Gen1Recomp 0.1.56 still has a few UI paths that do not send their labels
  -- through the string/status registries:
  --   * BattleState's level-up stat box draws ATTACK/... directly;
  --   * battle/item messages pass the stat name as a raw format argument;
  --   * SummaryMenu and PartyMenu draw BRN/PSN/... (and OK) directly.
  -- Keep this compatibility layer exact-value only.  In particular, never
  -- rewrite arbitrary strings: a player nickname must remain byte-for-byte
  -- what the player entered.  The normal string catalogue remains the source
  -- of truth for stat labels, while status_labels.lua remains the source of
  -- truth for condition labels.
  do
    local statLabelSources = {
      ATTACK = true,
      DEFENSE = true,
      SPEED = true,
      SPECIAL = true,
      ACCURACY = true,
      EVADE = true,
    }
    -- Only argument 2 is a stat label. Argument 1 is a nickname/trainer name
    -- and may itself literally be "ATTACK", so it must never be rewritten.
    local statArgumentPositions = {
      ["%s's\n%s\ngreatly rose!"] = 2,
      ["%s's\n%s rose!"] = 2,
      ["%s's\n%s fell!"] = 2,
      ["%s's\n%s\ngreatly fell!"] = 2,
      ["%s's %s\nrose!"] = 2,
    }

    local okStrings, Strings = pcall(require, "src.core.Strings")
    if okStrings and type(Strings) == "table"
        and type(Strings.get) == "function"
        and type(Strings.lookup) == "function" then
      -- Strings is callable through its current .get field, so replacing that
      -- field also covers MoveEffects, ItemEffects, and TrainerAI without
      -- reaching into their private local tables.  Store the current label set
      -- on the module so a dev-mode hot reload refreshes the wrapper's data.
      Strings.__zh_cn_stat_argument_labels = statLabelSources
      Strings.__zh_cn_stat_argument_positions = statArgumentPositions
      if not Strings.__zh_cn_stat_argument_compat then
        local get = Strings.get
        local unpack_ = unpack or table.unpack
        Strings.get = function(source, ...)
          local count = select("#", ...)
          if count == 0 then return get(source) end

          local labels = Strings.__zh_cn_stat_argument_labels or {}
          local position = (Strings.__zh_cn_stat_argument_positions or {})[source]
          local value = position and select(position, ...)
          if type(value) == "string" and labels[value] then
            local args = { ... }
            args[position] = Strings.lookup(value)
            return get(source, unpack_(args, 1, count))
          end
          return get(source, ...)
        end
        Strings.__zh_cn_stat_argument_compat = true
      end

      local okFont, Font = pcall(require, "src.render.Font")
      if okFont and type(Font) == "table" and type(Font.draw) == "function" then
        Font.__zh_cn_stat_labels = statLabelSources
        Font.__zh_cn_status_labels = statusLabels
        Font.__zh_cn_translate_ui_label = function(text, source, x, y)
          -- Font is a process-wide module and this wrapper intentionally
          -- survives dev hot reloads. If zh_cn is no longer in the merged
          -- string catalogue, become an identity function instead of leaving
          -- Chinese status labels behind after a hot-disable.
          if Strings.lookup("ATTACK") == "ATTACK" then return text end
          source = tostring(source or ""):gsub("\\", "/")
          local stats = Font.__zh_cn_stat_labels or {}
          local statuses = Font.__zh_cn_status_labels or {}
          local rawStatus = type(text) == "string"
              and text:match("^ ([A-Z][A-Z][A-Z])$")
          local function from(suffix)
            return source:sub(-#suffix) == suffix
          end

          local statBoxRow = x == 88
              and (y == 24 or y == 40 or y == 56 or y == 72)
          if stats[text] and statBoxRow
              and from("src/battle/BattleState.lua") then
            -- Level-up StatBox only. A nickname "ATTACK" drawn anywhere
            -- else is intentionally left untouched.
            return Strings.lookup(text)
          elseif (statuses[text] or text == "OK")
              and ((x == 128 and y == 48
                    and from("src/ui/SummaryMenu.lua"))
                   or (x == 136 and from("src/ui/PartyMenu.lua"))) then
            return statuses[text] or Strings.lookup(text)
          elseif statuses[rawStatus] and from("src/ui/Menu.lua") then
            -- Viridian School blackboard stores its five headings with a
            -- leading blank. Preserve that blank in the localized menu.
            return " " .. statuses[rawStatus]
          elseif text == " QUIT" and from("src/ui/Menu.lua") then
            return " " .. Strings.lookup("QUIT")
          end
          return text
        end
        if not Font.__zh_cn_ui_label_compat then
          local draw = Font.draw
          local function callerPath()
            if not (debug and debug.getinfo) then return "" end
            local info = debug.getinfo(3, "S")
            return tostring(info and info.source or ""):gsub("\\", "/")
          end
          Font.draw = function(text, x, y, ...)
            local translate = Font.__zh_cn_translate_ui_label
            if type(translate) == "function" then
              text = translate(text, callerPath(), x, y)
            end
            return draw(text, x, y, ...)
          end
          Font.__zh_cn_ui_label_compat = true
        end
      elseif not okFont then
        mod.log:warn("无法加载能力与状态标签的字体兼容层: %s",
                     tostring(Font))
      end
    elseif not okStrings then
      mod.log:warn("无法加载能力标签的动态文本兼容层: %s",
                   tostring(Strings))
    end
  end

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
