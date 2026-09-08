--- Simple dual-port RAM.
---
--- One write port, one read port, both on the same clock. Written in the
--- shape tools recognise for block RAM inference: a single clocked process,
--- no reset on the array, and a registered read address.
---
--- The read-during-write behaviour is the part people get wrong. This is
--- read-first: a read of the address being written returns the old contents.
--- Write-first needs a bypass, which costs a comparator and is not always
--- what the design wants, so it is left to the user.
local style = require("hdlsnip.style")

return {
  name = "ram_dp",
  trig = "ram",
  kind = "mem",
  scope = "design_unit",
  desc = "Simple dual-port RAM, read-first",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "ram_dp",
      desc = "Entity name",
    },
    {
      name = "width",
      type = "integer",
      default = 32,
      min = 1,
      max = 4096,
      desc = "Default data width",
    },
    {
      name = "depth",
      type = "integer",
      default = 1024,
      min = 2,
      max = 1048576,
      desc = "Default depth in words",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local width = style.name(cfg, "WIDTH", "generic")
    local depth = style.name(cfg, "DEPTH", "generic")
    local memory = style.name(cfg, "memory", "register")
    local lines = {}

    local function push(d, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(d) .. text)
    end
    local function name(base, kind)
      return style.name(cfg, base, kind)
    end

    local slv = ("std_logic_vector(%s - 1 %s 0)"):format(width, kw("downto"))
    local addr = ("natural %s 0 %s %s - 1"):format(kw("range"), kw("to"), depth)

    push(0, ("%s ieee;"):format(kw("library")))
    push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
    push(0, "")
    push(0, ("%s %s %s"):format(kw("entity"), params.name, kw("is")))
    push(1, ("%s ("):format(kw("generic")))
    for _, line in
      ipairs(style.align({
        { width, (": positive := %d;"):format(params.width) },
        { depth, (": positive := %d"):format(params.depth) },
      }))
    do
      push(2, line)
    end
    push(1, ");")

    local ports = { { cfg.clock.name, (": %s"):format(kw("in")), "std_logic" } }
    vim.list_extend(ports, {
      { name("we", "input"), (": %s"):format(kw("in")), "std_logic" },
      { name("wr_addr", "input"), (": %s"):format(kw("in")), addr },
      { name("wr_data", "input"), (": %s"):format(kw("in")), slv },
      { name("rd_addr", "input"), (": %s"):format(kw("in")), addr },
      { name("rd_data", "output"), (": %s"):format(kw("out")), slv },
    })
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
      ("%s t_memory %s %s (0 %s %s - 1) %s %s;"):format(
        kw("type"),
        kw("is"),
        kw("array"),
        kw("to"),
        depth,
        kw("of"),
        slv
      )
    )
    push(0, "")
    push(1, "-- No reset and no initial value: both prevent block RAM")
    push(1, "-- inference on some tools.")
    push(1, ("%s %s : t_memory;"):format(kw("signal"), memory))
    push(0, "")
    push(0, kw("begin"))
    push(0, "")
    local label = name("memory", "process")
    push(
      1,
      ("%s : %s (%s) %s"):format(label, kw("process"), cfg.clock.name, kw("is"))
    )
    push(1, kw("begin"))
    push(2, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
    push(
      3,
      ("%s %s = '1' %s"):format(kw("if"), name("we", "input"), kw("then"))
    )
    push(
      4,
      ("%s(%s) <= %s;"):format(
        memory,
        name("wr_addr", "input"),
        name("wr_data", "input")
      )
    )
    push(3, kw("end if") .. ";")
    push(3, "")
    push(3, "-- Read-first: a read of the address being written returns the")
    push(3, "-- old contents. Write-first needs an explicit bypass.")
    push(
      3,
      ("%s <= %s(%s);"):format(
        name("rd_data", "output"),
        memory,
        name("rd_addr", "input")
      )
    )
    push(2, kw("end if") .. ";")
    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), label))
    push(0, "")
    push(0, ("%s %s rtl;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
