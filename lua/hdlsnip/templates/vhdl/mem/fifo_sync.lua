--- Synchronous FIFO.
---
--- A design unit rather than a fragment, so a buffer is instantiated rather
--- than pasted. Single clock domain: crossing domains needs gray-coded
--- pointers, which is a different template.
---
--- The memory and the pointers live in separate processes on purpose. A
--- memory array written inside a process that also has an asynchronous reset
--- will not infer block RAM on most tools, because the reset applies to every
--- element. Pointers get the reset; the array does not.
local style = require("hdlsnip.style")

return {
  name = "fifo_sync",
  trig = "fifo",
  kind = "mem",
  scope = "design_unit",
  desc = "Synchronous FIFO with count-based flags",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "fifo_sync",
      desc = "Entity name",
    },
    {
      name = "width",
      type = "integer",
      default = 8,
      min = 1,
      max = 4096,
      desc = "Default data width",
    },
    {
      name = "depth",
      type = "integer",
      default = 16,
      min = 2,
      max = 65536,
      desc = "Default depth in words",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local has_reset = cfg.reset.style ~= "none"
    local width = style.name(cfg, "WIDTH", "generic")
    local depth = style.name(cfg, "DEPTH", "generic")
    local lines = {}

    local function push(depth_level, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(depth_level) .. text)
    end

    local function name(base, kind)
      return style.name(cfg, base, kind)
    end

    local wr_ptr = name("wr_ptr", "register")
    local rd_ptr = name("rd_ptr", "register")
    local count = name("count", "register")
    local memory = name("memory", "register")

    push(0, ("%s ieee;"):format(kw("library")))
    push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
    push(0, "")
    push(0, ("%s %s %s"):format(kw("entity"), params.name, kw("is")))

    local generics = style.align({
      { width, (": positive := %d;"):format(params.width) },
      { depth, (": positive := %d"):format(params.depth) },
    })
    push(1, ("%s ("):format(kw("generic")))
    for _, line in ipairs(generics) do
      push(2, line)
    end
    push(1, ");")

    local slv = ("std_logic_vector(%s - 1 %s 0)"):format(width, kw("downto"))
    local ports = { { cfg.clock.name, (": %s"):format(kw("in")), "std_logic" } }
    if has_reset then
      ports[#ports + 1] =
        { cfg.reset.name, (": %s"):format(kw("in")), "std_logic" }
    end
    vim.list_extend(ports, {
      { name("wr_en", "input"), (": %s"):format(kw("in")), "std_logic" },
      { name("wr_data", "input"), (": %s"):format(kw("in")), slv },
      { name("full", "output"), (": %s"):format(kw("out")), "std_logic" },
      { name("rd_en", "input"), (": %s"):format(kw("in")), "std_logic" },
      { name("rd_data", "output"), (": %s"):format(kw("out")), slv },
      { name("empty", "output"), (": %s"):format(kw("out")), "std_logic" },
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
    push(1, ("%s %s : t_memory;"):format(kw("signal"), memory))
    push(0, "")

    local counters = style.align({
      {
        wr_ptr,
        (": natural %s 0 %s %s - 1 := 0;"):format(kw("range"), kw("to"), depth),
      },
      {
        rd_ptr,
        (": natural %s 0 %s %s - 1 := 0;"):format(kw("range"), kw("to"), depth),
      },
      {
        count,
        (": natural %s 0 %s %s := 0;"):format(kw("range"), kw("to"), depth),
      },
    })
    for _, line in ipairs(counters) do
      push(1, kw("signal") .. " " .. line)
    end

    push(0, "")
    push(1, ("%s wr_go : boolean;"):format(kw("signal")))
    push(1, ("%s rd_go : boolean;"):format(kw("signal")))
    push(0, "")
    push(0, kw("begin"))
    push(0, "")

    -- A write to a full FIFO or a read from an empty one is ignored rather
    -- than corrupting the pointers, so a misbehaving master cannot desync it.
    push(1, "-- A write to a full FIFO, or a read from an empty one, is")
    push(1, "-- ignored: a misbehaving master must not desynchronise it.")
    push(
      1,
      ("wr_go <= %s = '1' %s %s < %s;"):format(
        name("wr_en", "input"),
        kw("and"),
        count,
        depth
      )
    )
    push(
      1,
      ("rd_go <= %s = '1' %s %s > 0;"):format(
        name("rd_en", "input"),
        kw("and"),
        count
      )
    )
    push(0, "")

    -- Memory: clocked only, never reset, so block RAM can be inferred.
    local mem_label = name("memory", "process")
    push(1, "-- No reset here: a reset on every element prevents block RAM")
    push(1, "-- inference on most tools.")
    push(
      1,
      ("%s : %s (%s) %s"):format(
        mem_label,
        kw("process"),
        cfg.clock.name,
        kw("is")
      )
    )
    push(1, kw("begin"))
    push(2, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
    push(3, ("%s wr_go %s"):format(kw("if"), kw("then")))
    push(4, ("%s(%s) <= %s;"):format(memory, wr_ptr, name("wr_data", "input")))
    push(3, kw("end if") .. ";")
    push(2, kw("end if") .. ";")
    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), mem_label))
    push(0, "")

    local ctrl_label = name("pointers", "process")
    push(
      1,
      ("%s : %s %s %s"):format(
        ctrl_label,
        kw("process"),
        style.sensitivity(cfg),
        kw("is")
      )
    )
    push(1, kw("begin"))

    local function body(depth_level)
      push(depth_level, ("%s wr_go %s"):format(kw("if"), kw("then")))
      push(
        depth_level + 1,
        ("%s <= (%s + 1) %s %s;"):format(wr_ptr, wr_ptr, kw("mod"), depth)
      )
      push(depth_level, kw("end if") .. ";")
      push(depth_level, "")
      push(depth_level, ("%s rd_go %s"):format(kw("if"), kw("then")))
      push(
        depth_level + 1,
        ("%s <= (%s + 1) %s %s;"):format(rd_ptr, rd_ptr, kw("mod"), depth)
      )
      push(depth_level, kw("end if") .. ";")
      push(depth_level, "")
      push(
        depth_level,
        "-- One update, so a simultaneous read and write is a no-op."
      )
      push(
        depth_level,
        ("%s wr_go %s %s rd_go %s"):format(
          kw("if"),
          kw("and"),
          kw("not"),
          kw("then")
        )
      )
      push(depth_level + 1, ("%s <= %s + 1;"):format(count, count))
      push(
        depth_level,
        ("%s rd_go %s %s wr_go %s"):format(
          kw("elsif"),
          kw("and"),
          kw("not"),
          kw("then")
        )
      )
      push(depth_level + 1, ("%s <= %s - 1;"):format(count, count))
      push(depth_level, kw("end if") .. ";")
    end

    local function reset_state(depth_level)
      push(depth_level, ("%s <= 0;"):format(wr_ptr))
      push(depth_level, ("%s <= 0;"):format(rd_ptr))
      push(depth_level, ("%s <= 0;"):format(count))
    end

    if cfg.reset.style == "async" then
      push(
        2,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      reset_state(3)
      push(
        2,
        ("%s %s %s"):format(kw("elsif"), style.clock_edge(cfg), kw("then"))
      )
      body(3)
      push(2, kw("end if") .. ";")
    elseif cfg.reset.style == "sync" then
      push(2, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      push(
        3,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      reset_state(4)
      push(3, kw("else"))
      body(4)
      push(3, kw("end if") .. ";")
      push(2, kw("end if") .. ";")
    else
      push(2, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      body(3)
      push(2, kw("end if") .. ";")
    end

    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), ctrl_label))
    push(0, "")

    -- Asynchronous read: distributed RAM, and the first word is available
    -- without a read strobe. Register it for block RAM, at the cost of a
    -- cycle of latency and a valid flag.
    push(1, "-- Asynchronous read, so the first word is available without a")
    push(1, "-- strobe. Register it for block RAM, at a cycle of latency.")
    push(1, ("%s <= %s(%s);"):format(name("rd_data", "output"), memory, rd_ptr))
    push(0, "")
    push(
      1,
      ("%s <= '1' %s %s = %s %s '0';"):format(
        name("full", "output"),
        kw("when"),
        count,
        depth,
        kw("else")
      )
    )
    push(
      1,
      ("%s <= '1' %s %s = 0 %s '0';"):format(
        name("empty", "output"),
        kw("when"),
        count,
        kw("else")
      )
    )
    push(0, "")
    push(0, ("%s %s rtl;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
