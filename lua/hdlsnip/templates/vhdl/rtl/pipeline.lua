--- Pipeline delay line.
---
--- N registers deep, so a signal can be aligned with something that took N
--- cycles elsewhere. The depth is a constant rather than repeated signal
--- declarations, which is what makes it adjustable later.
local style = require("hdlsnip.style")

return {
  name = "pipeline",
  trig = "pipe",
  kind = "rtl",
  scope = "mixed",
  desc = "N-stage delay line",
  dynamic = true,

  params = {
    {
      name = "sig",
      type = "identifier",
      default = "data",
      desc = "Signal base name",
    },
    {
      name = "width",
      type = "integer",
      default = 8,
      min = 1,
      max = 4096,
      desc = "Width in bits",
    },
    {
      name = "stages",
      type = "integer",
      default = 3,
      min = 1,
      max = 256,
      desc = "Delay in clock cycles",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local base = params.sig
    local type_name = "t_" .. base .. "_pipe"
    local chain = style.name(cfg, base .. "_pipe", "register")
    local input = base .. "_in"
    local output = base .. "_delayed"
    local label = style.name(cfg, base .. "_pipe", "process")
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
      ("%s %s %s %s (1 %s %d) %s %s;"):format(
        kw("type"),
        type_name,
        kw("is"),
        kw("array"),
        kw("to"),
        params.stages,
        kw("of"),
        slv
      )
    )
    decl("")
    decl(("%s %s : %s;"):format(kw("signal"), input, slv))
    decl(("%s %s : %s;"):format(kw("signal"), chain, type_name))
    decl(("%s %s : %s;"):format(kw("signal"), output, slv))

    local function body(depth)
      stmt(depth, ("%s(1) <= %s;"):format(chain, input))
      if params.stages > 1 then
        stmt(
          depth,
          ("%s(2 %s %d) <= %s(1 %s %d);"):format(
            chain,
            kw("to"),
            params.stages,
            chain,
            kw("to"),
            params.stages - 1
          )
        )
      end
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
      stmt(
        2,
        ("%s <= (%s => (%s => '0'));"):format(chain, kw("others"), kw("others"))
      )
      stmt(
        1,
        ("%s %s %s"):format(kw("elsif"), style.clock_edge(cfg), kw("then"))
      )
      body(2)
      stmt(1, kw("end if") .. ";")
    elseif cfg.reset.style == "sync" then
      stmt(1, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      stmt(
        2,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      stmt(
        3,
        ("%s <= (%s => (%s => '0'));"):format(chain, kw("others"), kw("others"))
      )
      stmt(2, kw("else"))
      body(3)
      stmt(2, kw("end if") .. ";")
      stmt(1, kw("end if") .. ";")
    else
      stmt(1, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      body(2)
      stmt(1, kw("end if") .. ";")
    end
    stmt(0, ("%s %s %s;"):format(kw("end"), kw("process"), label))
    stmt(0, "")
    stmt(0, ("%s <= %s(%d);"):format(output, chain, params.stages))

    return {
      declarations = table.concat(declarations, "\n"),
      statements = table.concat(statements, "\n"),
    }
  end,
}
