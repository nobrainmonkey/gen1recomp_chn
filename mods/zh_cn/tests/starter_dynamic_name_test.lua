-- Runtime regression for dynamic species names in gift dialogue.
-- Run as a POKEPORT_DRIVER with zh_cn enabled.  It exercises the public
-- script.command seam without opening a text box, so it is deterministic for
-- Red, Blue, and Yellow and does not require scripted input.

return function(game)
  local Runtime = require("src.mods.Runtime")

  local function dispatch(textId, value, pending)
    local seen
    local ctx = { game = game, pendingPokemonName = pending }
    local args = { textId, { RAM = value } }
    Runtime.call("script.command", function(_, command, forwarded)
      assert(command == "show_text", "unexpected command")
      -- Mirror Commands.show_text's replacement order: a pending species
      -- wins over the explicit row and is consumed by this message.
      seen = forwarded[2].RAM
      if ctx.pendingPokemonName then
        seen = ctx.pendingPokemonName
        ctx.pendingPokemonName = nil
      end
    end, ctx, "show_text", args)
    return seen, args[2].RAM
  end

  local cases = {
    { "_OaksLabReceivedMonText", "SQUIRTLE", "杰尼龟" },
    { "_OaksLabRivalReceivedMonText", "CHARMANDER", "小火龙" },
    { "_OaksLabReceivedText", "PIKACHU", "皮卡丘" },
    { "_GotMonText", "EEVEE", "伊布" },
    { "_Route23YouDontHaveTheBadgeYetText", "EARTHBADGE", "绿色徽章" },
    { "_Route23OhThatIsTheBadgeText", "VOLCANOBADGE", "深红徽章" },
  }
  for _, case in ipairs(cases) do
    local displayed, original = dispatch(case[1], case[2])
    assert(displayed == case[3], case[1] .. " displayed " .. tostring(displayed))
    assert(original == case[2], case[1] .. " mutated its shared script row")
  end

  -- Celadon gives Eevee before printing _GotMonText.  The engine's pending
  -- buffer used to overwrite the already-localized explicit substitution.
  local afterGive, original = dispatch("_GotMonText", "EEVEE", "EEVEE")
  assert(afterGive == "伊布", "pending gift species overwrote localized name")
  assert(original == "EEVEE", "pending gift mutated its shared script row")

  -- The rival's starter is an explicit counter-pick.  A stale buffer from a
  -- mod-supplied player nickname must not make both received boxes name the
  -- player's starter.
  local rivalGift = dispatch(
    "_OaksLabRivalReceivedMonText", "CHARMANDER", "SQUIRTLE")
  assert(rivalGift == "小火龙", "stale player starter replaced rival's starter")

  -- A nickname-bearing text is intentionally outside the gift whitelist.
  -- Even when it happens to equal a species id, preserve it byte-for-byte.
  local nickname = dispatch("_DoYouWantToNicknameText", "PIKACHU")
  assert(nickname == "PIKACHU", "nickname was mistaken for a species id")

  -- Unknown/future species ids also fall through rather than disappearing.
  local unknown = dispatch("_GotMonText", "FUTURE_MON")
  assert(unknown == "FUTURE_MON", "unknown species did not fall through")
  local arbitrary = dispatch(
    "_Route23OhThatIsTheBadgeText", "PLAYER_BADGE_VALUE")
  assert(arbitrary == "PLAYER_BADGE_VALUE",
    "arbitrary badge-buffer value did not fall through")

  -- A receipt-before-give marker may clear only the matching species that
  -- give_pokemon wrote.  Preserve a different pending value produced by a
  -- pokemon.before_give transformation.
  local function receiptThenGive(actualSpecies)
    local ctx = { game = game }
    Runtime.call("script.command", function() end, ctx, "show_text", {
      "_OaksLabReceivedText", { RAM = "PIKACHU" },
    })
    Runtime.call("script.command", function()
      ctx.pendingPokemonName = actualSpecies
    end, ctx, "give_pokemon", { "PIKACHU", 5, true })
    return ctx.pendingPokemonName
  end
  assert(receiptThenGive("PIKACHU") == nil,
    "Yellow receipt-before-give buffer remained stale")
  assert(receiptThenGive("MEW") == "MEW",
    "transformed pending species was cleared as stale")

  -- Exercise the real ScriptRunner -> Commands.show_text -> TextBox path as
  -- well, rather than testing only the hook's forwarded arguments.
  local ScriptRunner = require("src.script.ScriptRunner")
  local GameVersion = require("src.core.GameVersion")
  local function runToTextBox(rows)
    while game.stack:top() do game.stack:pop() end
    local runner = ScriptRunner.new(game, nil)
    runner:run(rows, {})
    local box = assert(game.stack:top(), "script did not open a text box")
    assert(type(box.pages) == "table", "top state is not a text box")
    local lines = {}
    for _, page in ipairs(box.pages) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    local rendered = table.concat(lines, "\n")
    game.stack:pop()
    if box.onDone then box.onDone() end
    return rendered, runner.ctx
  end

  local version = GameVersion.get()
  local starterText, starterId, starterName
  if version == "yellow" then
    starterText, starterId, starterName =
      "_OaksLabReceivedText", "PIKACHU", "皮卡丘"
  else
    starterText, starterId, starterName =
      "_OaksLabReceivedMonText", "SQUIRTLE", "杰尼龟"
  end
  local rendered = runToTextBox({
    { "show_text", starterText, { RAM = starterId } },
  })
  assert(rendered:find(starterName, 1, true),
    version .. " starter box omitted " .. starterName .. ": " .. rendered)
  assert(not rendered:find(starterId, 1, true),
    version .. " starter box leaked raw id " .. starterId)

  for _, badge in ipairs({
    { "_Route23YouDontHaveTheBadgeYetText", "EARTHBADGE", "绿色徽章" },
    { "_Route23OhThatIsTheBadgeText", "VOLCANOBADGE", "深红徽章" },
  }) do
    rendered = runToTextBox({
      { "show_text", badge[1], { RAM = badge[2] } },
    })
    assert(rendered:find(badge[3], 1, true),
      version .. " badge box omitted " .. badge[3] .. ": " .. rendered)
    assert(not rendered:find(badge[2], 1, true),
      version .. " badge box leaked raw id " .. badge[2])
  end

  -- Reproduce the after-give ordering used by Celadon Eevee.  skipNickname
  -- only keeps this automated test non-interactive; pendingPokemonName and
  -- the received-text path are identical to the real gift flow.
  rendered = runToTextBox({
    { "give_pokemon", "EEVEE", 25, true },
    { "show_text", "_GotMonText", { RAM = "EEVEE" } },
  })
  assert(rendered:find("伊布", 1, true),
    version .. " post-give box omitted 伊布: " .. rendered)
  assert(not rendered:find("EEVEE", 1, true),
    version .. " post-give box leaked raw EEVEE")

  if version == "yellow" then
    local yellowCtx
    rendered, yellowCtx = runToTextBox({
      { "show_text", "_OaksLabReceivedText", { RAM = "PIKACHU" } },
      { "give_pokemon", "PIKACHU", 5, true },
    })
    assert(rendered:find("皮卡丘", 1, true),
      "Yellow receipt-before-give box omitted 皮卡丘")
    assert(yellowCtx.pendingPokemonName == nil,
      "Yellow give_pokemon left PIKACHU stale after its prior receipt")
  end

  local message =
    "PASS: dynamic starter/gift and Route 23 badge names are localized safely"
  local logPath = os.getenv("ZH_CN_TEST_LOG")
  if logPath then
    local file = assert(io.open(logPath, "wb"))
    file:write(message, "\n")
    file:close()
  end
  print("[zh_cn] " .. message)
end
