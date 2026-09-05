--- Single-bit clock domain crossing synchroniser.
---
--- Emitted as a reusable design unit rather than a fragment, so it can be
--- instantiated wherever a bit crosses domains instead of being pasted in
--- repeatedly. The stage count is a VHDL generic rather than a Lua parameter,
--- since the depth is a property of the instance, not of the template.
---
--- The vendor attribute is the reason this is generated rather than copied: it
--- differs per family, and it must be declared exactly once in a declarative
--- region, which is easy to get wrong by hand.
local style = require("hdlsnip.style")

--- Attribute that tells the place and route tool these registers form a
--- synchroniser and must not be optimised, retimed or spread apart.
---@param cfg table
---@param signal string
---@return string[]
local function vendor_attributes(cfg, signal)
  local kw = style.kw(cfg)
  if cfg.vendor == "amd" then
    return {
      ("%s async_reg : string;"):format(kw("attribute")),
      ('%s async_reg %s %s : %s %s "TRUE";'):format(
        kw("attribute"),
        kw("of"),
        signal,
        kw("signal"),
        kw("is")
      ),
    }
  end
  if cfg.vendor == "intel" then
    return {
      ("%s preserve : boolean;"):format(kw("attribute")),
      ("%s preserve %s %s : %s %s true;"):format(
        kw("attribute"),
        kw("of"),
        signal,
        kw("signal"),
        kw("is")
      ),
    }
  end
  return {}
end

return {
  name = "bit_sync",
  trig = "cdc",
  kind = "cdc",
  scope = "design_unit",
  desc = "Single-bit CDC synchroniser entity",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "bit_sync",
      desc = "Entity name",
    },
    {
      name = "stages",
      type = "integer",
      default = 2,
      min = 2,
      max = 8,
      desc = "Default number of synchroniser stages",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local reg = style.name(cfg, "sync", "register")
    local lines = {}

    local function push(depth, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(depth) .. text)
    end

    push(0, ("%s ieee;"):format(kw("library")))
    push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
    push(0, "")
    push(0, "-- Single-bit synchroniser.")
    push(0, "--")
    push(0, "-- Valid for one bit at a time. A bus, or several bits that must")
    push(0, "-- stay mutually consistent, needs a handshake or a gray coded")
    push(0, "-- pointer instead: each bit here settles independently.")
    push(0, "--")
    push(
      0,
      "-- Constrain the source register with set_max_delay -datapath_only"
    )
    push(0, "-- so the crossing is not timed as a normal path.")
    push(0, ("%s %s %s"):format(kw("entity"), params.name, kw("is")))

    local generics = style.align({
      {
        style.name(cfg, "STAGES", "generic"),
        (": positive := %d;"):format(params.stages),
      },
      { style.name(cfg, "INIT", "generic"), ": std_logic := '0'" },
    })
    push(1, ("%s ("):format(kw("generic")))
    for _, line in ipairs(generics) do
      push(2, line)
    end
    push(1, ");")

    local ports = { { cfg.clock.name, (": %s"):format(kw("in")), "std_logic" } }
    if cfg.reset.style ~= "none" then
      ports[#ports + 1] =
        { cfg.reset.name, (": %s"):format(kw("in")), "std_logic" }
    end
    ports[#ports + 1] =
      { style.name(cfg, "d", "input"), (": %s"):format(kw("in")), "std_logic" }
    ports[#ports + 1] = {
      style.name(cfg, "q", "output"),
      (": %s"):format(kw("out")),
      "std_logic",
    }

    push(1, ("%s ("):format(kw("port")))
    local aligned = style.align(ports)
    for index, line in ipairs(aligned) do
      push(2, line .. (index < #aligned and ";" or ""))
    end
    push(1, ");")
    push(0, ("%s %s %s;"):format(kw("end"), kw("entity"), params.name))
    push(0, "")

    push(
      0,
      ("%s rtl %s %s %s"):format(
        kw("architecture"),
        kw("of"),
        params.name,
        kw("is")
      )
    )
    push(0, "")
    push(
      1,
      ("%s %s : std_logic_vector(%s - 1 %s 0) := (%s => %s);"):format(
        kw("signal"),
        reg,
        style.name(cfg, "STAGES", "generic"),
        kw("downto"),
        kw("others"),
        style.name(cfg, "INIT", "generic")
      )
    )

    local attributes = vendor_attributes(cfg, reg)
    if #attributes > 0 then
      push(0, "")
      for _, line in ipairs(attributes) do
        push(1, line)
      end
    end

    push(0, "")
    push(0, kw("begin"))
    push(0, "")

    -- One stage is a register, not a synchroniser. Catching it at elaboration
    -- is cheaper than debugging metastability on hardware.
    push(
      1,
      ("%s %s >= 2"):format(kw("assert"), style.name(cfg, "STAGES", "generic"))
    )
    push(
      2,
      ('%s "%s: needs at least two stages"'):format(kw("report"), params.name)
    )
    push(2, ("%s %s;"):format(kw("severity"), kw("failure")))
    push(0, "")

    local label = style.name(cfg, "sync", "process")
    push(
      1,
      ("%s : %s %s %s"):format(
        label,
        kw("process"),
        style.sensitivity(cfg),
        kw("is")
      )
    )
    push(1, kw("begin"))

    local shift = ("%s <= %s(%s'high - 1 %s 0) & %s;"):format(
      reg,
      reg,
      reg,
      kw("downto"),
      style.name(cfg, "d", "input")
    )
    local clear = ("%s <= (%s => %s);"):format(
      reg,
      kw("others"),
      style.name(cfg, "INIT", "generic")
    )

    if cfg.reset.style == "async" then
      push(
        2,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      push(3, clear)
      push(
        2,
        ("%s %s %s"):format(kw("elsif"), style.clock_edge(cfg), kw("then"))
      )
      push(3, shift)
      push(2, kw("end if") .. ";")
    elseif cfg.reset.style == "sync" then
      push(2, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      push(
        3,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      push(4, clear)
      push(3, kw("else"))
      push(4, shift)
      push(3, kw("end if") .. ";")
      push(2, kw("end if") .. ";")
    else
      push(2, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      push(3, shift)
      push(2, kw("end if") .. ";")
    end

    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), label))
    push(0, "")
    push(
      1,
      ("%s <= %s(%s'high);"):format(style.name(cfg, "q", "output"), reg, reg)
    )
    push(0, "")
    push(0, ("%s %s rtl;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
