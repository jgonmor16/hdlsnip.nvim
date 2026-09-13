--- Edge detector producing a one-cycle pulse.
---
--- The delayed copy is the whole circuit, and the direction decides which way
--- the comparison goes. Written by hand it is usually right; written by hand
--- at the end of a long day it is usually inverted.
local style = require("hdlsnip.style")

return {
  name = "edge_detect",
  trig = "edge",
  kind = "rtl",
  scope = "mixed",
  desc = "One-cycle pulse on a rising, falling or either edge",
  dynamic = true,

  params = {
    {
      name = "sig",
      type = "identifier",
      default = "flag",
      desc = "Signal to watch",
    },
    {
      name = "edge",
      type = "choice",
      choices = { "rising", "falling", "both" },
      default = "rising",
      desc = "Edge to detect",
    },
  },

  fixture_declarations = function(cfg, params)
    -- The watched signal belongs to the user's design; the fixture needs it
    -- declared to analyse, and the inserted code must not redeclare it.
    -- `params` carries only what a case overrode, so the default applies
    -- when it did not vary this one.
    local watched = (params or {}).sig or "flag"
    return { ("signal %s : std_logic;"):format(watched) }
  end,

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local watched = params.sig
    local delayed = style.name(cfg, params.sig .. "_d", "register")
    local pulse = params.sig .. "_" .. params.edge
    local label = style.name(cfg, params.sig .. "_edge", "process")
    local declarations, statements = {}, {}

    declarations[#declarations + 1] = ("%s %s : std_logic := '0';"):format(
      kw("signal"),
      delayed
    )
    declarations[#declarations + 1] = ("%s %s : std_logic;"):format(
      kw("signal"),
      pulse
    )

    local function stmt(depth, text)
      statements[#statements + 1] = text == "" and ""
        or (ind:rep(depth) .. text)
    end

    stmt(
      0,
      ("%s : %s %s %s"):format(
        label,
        kw("process"),
        style.sensitivity(cfg),
        kw("is")
      )
    )
    stmt(0, kw("begin"))
    if cfg.reset.style == "async" then
      stmt(
        1,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      stmt(2, ("%s <= '0';"):format(delayed))
      stmt(
        1,
        ("%s %s %s"):format(kw("elsif"), style.clock_edge(cfg), kw("then"))
      )
      stmt(2, ("%s <= %s;"):format(delayed, watched))
      stmt(1, kw("end if") .. ";")
    elseif cfg.reset.style == "sync" then
      stmt(1, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      stmt(
        2,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      stmt(3, ("%s <= '0';"):format(delayed))
      stmt(2, kw("else"))
      stmt(3, ("%s <= %s;"):format(delayed, watched))
      stmt(2, kw("end if") .. ";")
      stmt(1, kw("end if") .. ";")
    else
      stmt(1, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      stmt(2, ("%s <= %s;"):format(delayed, watched))
      stmt(1, kw("end if") .. ";")
    end
    stmt(0, ("%s %s %s;"):format(kw("end"), kw("process"), label))
    stmt(0, "")

    local expression
    if params.edge == "rising" then
      expression = ("%s %s %s %s"):format(
        watched,
        kw("and"),
        kw("not"),
        delayed
      )
    elseif params.edge == "falling" then
      expression = ("%s %s %s %s"):format(
        kw("not"),
        watched,
        kw("and"),
        delayed
      )
    else
      expression = ("%s %s %s"):format(watched, kw("xor"), delayed)
    end
    stmt(0, ("%s <= %s;"):format(pulse, expression))

    return {
      declarations = table.concat(declarations, "\n"),
      statements = table.concat(statements, "\n"),
    }
  end,
}
