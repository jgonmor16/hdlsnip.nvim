--- Multiplexer over an array of inputs.
---
--- An array rather than N separate signals, so the width is a generic and the
--- select is a plain index. Written with `when others` on purpose: without it
--- a select value outside the range infers a latch.
local style = require("hdlsnip.style")

return {
  name = "mux",
  trig = "mux",
  kind = "rtl",
  scope = "mixed",
  desc = "Multiplexer, combinational or registered",
  dynamic = true,

  params = {
    {
      name = "sig",
      type = "identifier",
      default = "mux",
      desc = "Signal base name",
    },
    {
      name = "inputs",
      type = "integer",
      default = 4,
      min = 2,
      max = 256,
      desc = "Number of inputs",
    },
    {
      name = "width",
      type = "integer",
      default = 8,
      min = 1,
      max = 4096,
      desc = "Width of each input",
    },
    {
      name = "output",
      type = "choice",
      choices = { "combinational", "registered" },
      default = "combinational",
      desc = "Whether the result is registered",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local base = params.sig
    local type_name = "t_" .. base .. "_inputs"
    local inputs = base .. "_in"
    local sel = base .. "_sel"
    local result = params.output == "registered"
        and style.name(cfg, base .. "_out", "register")
      or base .. "_out"
    local declarations, statements = {}, {}

    local function decl(text)
      declarations[#declarations + 1] = text
    end
    local function stmt(depth, text)
      statements[#statements + 1] = text == "" and ""
        or (ind:rep(depth) .. text)
    end

    local slv = ("std_logic_vector(%d %s 0)"):format(
      params.width - 1,
      kw("downto")
    )
    decl(
      ("%s %s %s %s (0 %s %d) %s %s;"):format(
        kw("type"),
        type_name,
        kw("is"),
        kw("array"),
        kw("to"),
        params.inputs - 1,
        kw("of"),
        slv
      )
    )
    decl("")
    decl(("%s %s : %s;"):format(kw("signal"), inputs, type_name))
    decl(
      ("%s %s : natural %s 0 %s %d;"):format(
        kw("signal"),
        sel,
        kw("range"),
        kw("to"),
        params.inputs - 1
      )
    )
    decl(("%s %s : %s;"):format(kw("signal"), result, slv))

    if params.output == "combinational" then
      stmt(0, ("%s <= %s(%s);"):format(result, inputs, sel))
    else
      local label = style.name(cfg, base, "process")
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
        stmt(2, ("%s <= (%s => '0');"):format(result, kw("others")))
        stmt(
          1,
          ("%s %s %s"):format(kw("elsif"), style.clock_edge(cfg), kw("then"))
        )
        stmt(2, ("%s <= %s(%s);"):format(result, inputs, sel))
        stmt(1, kw("end if") .. ";")
      elseif cfg.reset.style == "sync" then
        stmt(
          1,
          ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then"))
        )
        stmt(
          2,
          ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
        )
        stmt(3, ("%s <= (%s => '0');"):format(result, kw("others")))
        stmt(2, kw("else"))
        stmt(3, ("%s <= %s(%s);"):format(result, inputs, sel))
        stmt(2, kw("end if") .. ";")
        stmt(1, kw("end if") .. ";")
      else
        stmt(
          1,
          ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then"))
        )
        stmt(2, ("%s <= %s(%s);"):format(result, inputs, sel))
        stmt(1, kw("end if") .. ";")
      end
      stmt(0, ("%s %s %s;"):format(kw("end"), kw("process"), label))
    end

    return {
      declarations = table.concat(declarations, "\n"),
      statements = table.concat(statements, "\n"),
    }
  end,
}
