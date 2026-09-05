--- Clocked process.
---
--- The most-used fragment in any VHDL codebase, and the one whose shape
--- changes most with configuration: an asynchronous reset is a branch outside
--- the clock test, a synchronous reset is a branch inside it, and no reset is
--- neither. Getting that wrong is a synthesis mismatch rather than a syntax
--- error, which is why it is generated rather than typed.
local style = require("hdlsnip.style")

return {
  name = "process",
  trig = "prc",
  kind = "rtl",
  scope = "statement",
  desc = "Clocked process with the configured reset",
  dynamic = true,

  params = {
    {
      name = "label",
      type = "identifier",
      default = "main",
      desc = "Process label, without the configured prefix",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local label = style.name(cfg, params.label, "process")
    local edge = style.clock_edge(cfg)
    local lines = {}

    local function push(depth, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(depth) .. text)
    end

    push(
      0,
      ("%s : %s %s %s"):format(
        label,
        kw("process"),
        style.sensitivity(cfg),
        kw("is")
      )
    )
    push(0, kw("begin"))

    if cfg.reset.style == "async" then
      -- Asynchronous: the reset branch sits outside the clock test, which is
      -- what makes it asynchronous. Moving it inside silently changes the
      -- hardware.
      push(
        1,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      push(2, "-- reset state")
      push(1, ("%s %s %s"):format(kw("elsif"), edge, kw("then")))
      push(2, "-- clocked logic")
      push(1, kw("end if") .. ";")
    elseif cfg.reset.style == "sync" then
      push(1, ("%s %s %s"):format(kw("if"), edge, kw("then")))
      push(
        2,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      push(3, "-- reset state")
      push(2, kw("else"))
      push(3, "-- clocked logic")
      push(2, kw("end if") .. ";")
      push(1, kw("end if") .. ";")
    else
      push(1, ("%s %s %s"):format(kw("if"), edge, kw("then")))
      push(2, "-- clocked logic")
      push(1, kw("end if") .. ";")
    end

    push(0, ("%s %s %s;"):format(kw("end"), kw("process"), label))
    return table.concat(lines, "\n")
  end,
}
