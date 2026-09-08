--- Counter with a configurable end behaviour.
---
--- Wrapping and saturating are one word apart in English and a different
--- circuit in hardware, which is why it is a choice rather than a comment.
local style = require("hdlsnip.style")

return {
  name = "counter",
  trig = "cnt",
  kind = "rtl",
  scope = "mixed",
  desc = "Counter that wraps or saturates",
  dynamic = true,

  params = {
    {
      name = "sig",
      type = "identifier",
      default = "count",
      desc = "Signal name",
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
      name = "at_end",
      type = "choice",
      choices = { "wrap", "saturate" },
      default = "wrap",
      desc = "Behaviour at the maximum value",
    },
  },

  fixture_declarations = function(cfg)
    return {
      ("signal %s : std_logic;"):format(style.name(cfg, "count_en", "signal")),
    }
  end,

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local counter = style.name(cfg, params.sig, "register")
    local enable = style.name(cfg, "count_en", "signal")
    local label = style.name(cfg, params.sig, "process")
    local declarations, statements = {}, {}

    local function decl(text)
      declarations[#declarations + 1] = text
    end
    local function stmt(depth, text)
      statements[#statements + 1] = text == "" and ""
        or (ind:rep(depth) .. text)
    end

    decl(
      ("%s %s : unsigned(%d %s 0) := (%s => '0');"):format(
        kw("signal"),
        counter,
        params.width - 1,
        kw("downto"),
        kw("others")
      )
    )

    local function body(depth)
      stmt(depth, ("%s %s = '1' %s"):format(kw("if"), enable, kw("then")))
      if params.at_end == "saturate" then
        stmt(
          depth + 1,
          ("%s %s /= (%s'range => '1') %s"):format(
            kw("if"),
            counter,
            counter,
            kw("then")
          )
        )
        stmt(depth + 2, ("%s <= %s + 1;"):format(counter, counter))
        stmt(depth + 1, kw("end if") .. ";")
      else
        stmt(depth + 1, ("%s <= %s + 1;"):format(counter, counter))
      end
      stmt(depth, kw("end if") .. ";")
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
      stmt(2, ("%s <= (%s => '0');"):format(counter, kw("others")))
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
      stmt(3, ("%s <= (%s => '0');"):format(counter, kw("others")))
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

    return {
      declarations = table.concat(declarations, "\n"),
      statements = table.concat(statements, "\n"),
    }
  end,
}
