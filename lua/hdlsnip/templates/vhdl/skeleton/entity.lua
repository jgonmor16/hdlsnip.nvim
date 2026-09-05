--- Entity and architecture skeleton.
---
--- Dynamic because the port list depends on configuration rather than on a
--- parameter: a design with no reset must not get a reset port, and the
--- columns are aligned against whichever port names the configuration
--- produced.
local style = require("hdlsnip.style")

return {
  name = "entity",
  trig = "ent",
  kind = "skeleton",
  scope = "design_unit",
  desc = "Entity with matching architecture",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "top",
      desc = "Entity name",
    },
    {
      name = "arch",
      type = "identifier",
      default = "rtl",
      desc = "Architecture name",
    },
    {
      name = "generics",
      type = "boolean",
      default = false,
      desc = "Include a generic clause",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local lines = {}

    local function push(...)
      for _, line in ipairs({ ... }) do
        lines[#lines + 1] = line
      end
    end

    push(
      ("%s ieee;"):format(kw("library")),
      ("%s%s ieee.std_logic_1164.%s;"):format(ind, kw("use"), kw("all")),
      ("%s%s ieee.numeric_std.%s;"):format(ind, kw("use"), kw("all")),
      "",
      ("%s %s %s"):format(kw("entity"), params.name, kw("is"))
    )

    if params.generics then
      local generic = style.name(cfg, "WIDTH", "generic")
      push(
        ("%s%s ("):format(ind, kw("generic")),
        -- `positive` is a predefined type, not a reserved word, so it is
        -- not subject to keyword casing.
        ("%s%s : positive := 8"):format(ind:rep(2), generic),
        ("%s);"):format(ind)
      )
    end

    -- Ports are built as rows and aligned together, so the colons line up
    -- whatever the configured clock and reset names are.
    local rows = { { cfg.clock.name, (": %s"):format(kw("in")), "std_logic" } }
    if cfg.reset.style ~= "none" then
      rows[#rows + 1] =
        { cfg.reset.name, (": %s"):format(kw("in")), "std_logic" }
    end

    push(("%s%s ("):format(ind, kw("port")))
    local aligned = style.align(rows)
    for index, line in ipairs(aligned) do
      -- The last port declaration takes no semicolon; the closing paren of
      -- the port clause ends it.
      local sep = index < #aligned and ";" or ""
      push(ind:rep(2) .. line .. sep)
    end
    push(("%s);"):format(ind))

    push(
      ("%s %s %s;"):format(kw("end"), kw("entity"), params.name),
      "",
      ("%s %s %s %s %s"):format(
        kw("architecture"),
        params.arch,
        kw("of"),
        params.name,
        kw("is")
      ),
      "",
      kw("begin"),
      "",
      ("%s %s %s;"):format(kw("end"), kw("architecture"), params.arch)
    )

    return table.concat(lines, "\n")
  end,
}
