--- Asynchronous FIFO, gray-coded pointers.
---
--- The design `cdc_handshake` points at for streams. A handshake costs a
--- round trip per word; this sustains one word per clock in each domain.
---
--- Why gray code: the pointers cross domains, and a binary pointer going from
--- 0111 to 1000 changes four bits at once. Sampled mid-transition the reader
--- could see any of sixteen values, several of them far from either. A gray
--- pointer changes one bit per increment, so a mid-transition sample is
--- always either the old value or the new one -- never a third.
---
--- The pointers carry one bit more than the address needs. That extra bit is
--- what distinguishes full from empty when the two pointers are equal: equal
--- including the extra bit means empty, equal except for the top two bits
--- means the writer has lapped the reader.
---
--- Both flags are conservative. `full` can be asserted when a read has just
--- freed a slot the writer has not seen yet, and `empty` when a write has not
--- yet crossed. Never the other way round, which is what matters.
local style = require("hdlsnip.style")

--- Address bits for `depth` words, which must be a power of two.
---@param depth integer
---@return integer
local function address_width(depth)
  local bits = 1
  while (2 ^ bits) < depth do
    bits = bits + 1
  end
  return bits
end

return {
  name = "fifo_async",
  trig = "afifo",
  kind = "mem",
  scope = "design_unit",
  desc = "Asynchronous FIFO with gray-coded pointers",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "fifo_async",
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
      default = 16,
      min = 2,
      max = 65536,
      desc = "Default depth, rounded up to a power of two",
    },
    {
      name = "stages",
      type = "integer",
      default = 2,
      min = 2,
      max = 8,
      desc = "Default synchroniser stages",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local width = style.name(cfg, "WIDTH", "generic")
    local addr = style.name(cfg, "ADDR_WIDTH", "generic")
    local stages = style.name(cfg, "STAGES", "generic")
    local lines = {}

    local function push(depth, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(depth) .. text)
    end
    local function name(base, kind)
      return style.name(cfg, base, kind)
    end

    local slv = ("std_logic_vector(%s - 1 %s 0)"):format(width, kw("downto"))
    local ptr = ("unsigned(%s %s 0)"):format(addr, kw("downto"))
    local gray = ("std_logic_vector(%s %s 0)"):format(addr, kw("downto"))

    push(0, ("%s ieee;"):format(kw("library")))
    push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
    push(1, ("%s ieee.numeric_std.%s;"):format(kw("use"), kw("all")))
    push(0, "")
    push(0, "-- Asynchronous FIFO.")
    push(0, "--")
    push(0, "-- The pointers are gray coded because they cross domains: a")
    push(0, "-- binary pointer going from 0111 to 1000 changes four bits at")
    push(0, "-- once, and a mid-transition sample could read any of sixteen")
    push(0, "-- values. One bit changes per gray increment, so a sample is")
    push(0, "-- always the old value or the new one.")
    push(0, "--")
    push(0, "-- Constrain both pointer crossings with set_max_delay")
    push(0, "-- -datapath_only. The memory is not constrained: the write")
    push(0, "-- pointer reaching the reader is what makes the data safe.")
    push(0, ("%s %s %s"):format(kw("entity"), params.name, kw("is")))

    local bits = address_width(params.depth)
    local generics = style.align({
      { width, (": positive := %d;"):format(params.width) },
      { addr, (": positive := %d;"):format(bits) },
      { stages, (": positive := %d"):format(params.stages) },
    })
    push(1, ("%s ("):format(kw("generic")))
    for _, line in ipairs(generics) do
      push(2, line)
    end
    push(1, ");")

    local ports = style.align({
      { "wr_clk", (": %s"):format(kw("in")), "std_logic" },
      { "wr_rst_n", (": %s"):format(kw("in")), "std_logic" },
      { name("wr_en", "input"), (": %s"):format(kw("in")), "std_logic" },
      { name("wr_data", "input"), (": %s"):format(kw("in")), slv },
      { name("full", "output"), (": %s"):format(kw("out")), "std_logic" },
      { "rd_clk", (": %s"):format(kw("in")), "std_logic" },
      { "rd_rst_n", (": %s"):format(kw("in")), "std_logic" },
      { name("rd_en", "input"), (": %s"):format(kw("in")), "std_logic" },
      { name("rd_data", "output"), (": %s"):format(kw("out")), slv },
      { name("empty", "output"), (": %s"):format(kw("out")), "std_logic" },
    })
    push(1, ("%s ("):format(kw("port")))
    for index, line in ipairs(ports) do
      push(2, line .. (index < #ports and ";" or ""))
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
      -- The index type is named because VHDL-93 cannot infer it when one
      -- bound is a universal integer and the other involves an exponent.
      ("%s t_memory %s %s (natural %s 0 %s 2 ** %s - 1) %s %s;"):format(
        kw("type"),
        kw("is"),
        kw("array"),
        kw("range"),
        kw("to"),
        addr,
        kw("of"),
        slv
      )
    )
    push(0, "")
    push(1, "-- No reset and no initial value, so block RAM is inferred.")
    push(
      1,
      ("%s %s : t_memory;"):format(kw("signal"), name("memory", "register"))
    )
    push(0, "")

    push(1, "-- One bit wider than the address: the extra bit is what tells")
    push(1, "-- full from empty when the pointers are otherwise equal.")
    local declarations = style.align({
      {
        name("wr_bin", "register"),
        (": %s := (%s => '0');"):format(ptr, kw("others")),
      },
      {
        name("wr_gray", "register"),
        (": %s := (%s => '0');"):format(gray, kw("others")),
      },
      {
        name("rd_bin", "register"),
        (": %s := (%s => '0');"):format(ptr, kw("others")),
      },
      {
        name("rd_gray", "register"),
        (": %s := (%s => '0');"):format(gray, kw("others")),
      },
    })
    for _, line in ipairs(declarations) do
      push(1, kw("signal") .. " " .. line)
    end
    push(0, "")
    push(1, "-- Each pointer synchronised into the other domain. A new")
    push(1, "-- sample enters at index 1 and the settled value leaves at")
    push(1, "-- STAGES, which is the end the flags read: reading the other")
    push(1, "-- end compares against a value that has crossed nothing.")
    local syncs = style.align({
      {
        name("rd_gray_wr", "register"),
        (": %s := (%s => (%s => '0'));"):format(
          ("%s_array"):format("t_sync"),
          kw("others"),
          kw("others")
        ),
      },
    })
    push(
      1,
      ("%s t_sync_array %s %s (1 %s %s) %s %s;"):format(
        kw("type"),
        kw("is"),
        kw("array"),
        kw("to"),
        stages,
        kw("of"),
        gray
      )
    )
    push(0, "")
    for _, line in ipairs(syncs) do
      push(1, kw("signal") .. " " .. line)
    end
    push(
      1,
      ("%s %s : t_sync_array := (%s => (%s => '0'));"):format(
        kw("signal"),
        name("wr_gray_rd", "register"),
        kw("others"),
        kw("others")
      )
    )

    if cfg.vendor == "amd" then
      push(0, "")
      push(1, ("%s async_reg : string;"):format(kw("attribute")))
      push(
        1,
        ('%s async_reg %s %s : %s %s "TRUE";'):format(
          kw("attribute"),
          kw("of"),
          name("rd_gray_wr", "register"),
          kw("signal"),
          kw("is")
        )
      )
      push(
        1,
        ('%s async_reg %s %s : %s %s "TRUE";'):format(
          kw("attribute"),
          kw("of"),
          name("wr_gray_rd", "register"),
          kw("signal"),
          kw("is")
        )
      )
    end

    push(0, "")
    push(1, ("%s wr_go : boolean;"):format(kw("signal")))
    push(1, ("%s rd_go : boolean;"):format(kw("signal")))
    push(1, ("%s %s : std_logic;"):format(kw("signal"), name("full", "signal")))
    push(
      1,
      ("%s %s : std_logic;"):format(kw("signal"), name("empty", "signal"))
    )
    push(0, "")
    push(0, kw("begin"))
    push(0, "")

    local wr_bin = name("wr_bin", "register")
    local wr_gray_r = name("wr_gray", "register")
    local rd_bin = name("rd_bin", "register")
    local rd_gray_r = name("rd_gray", "register")
    local rd_sync = name("rd_gray_wr", "register")
    local wr_sync = name("wr_gray_rd", "register")
    local memory = name("memory", "register")
    local full = name("full", "signal")
    local empty = name("empty", "signal")

    push(
      1,
      ("wr_go <= %s = '1' %s %s = '0';"):format(
        name("wr_en", "input"),
        kw("and"),
        full
      )
    )
    push(
      1,
      ("rd_go <= %s = '1' %s %s = '0';"):format(
        name("rd_en", "input"),
        kw("and"),
        empty
      )
    )
    push(0, "")

    -- Write domain
    push(1, "-- Write domain.")
    push(
      1,
      ("%s : %s (wr_clk) %s"):format(
        name("memory", "process"),
        kw("process"),
        kw("is")
      )
    )
    push(1, kw("begin"))
    push(
      2,
      ("%s %s(wr_clk) %s"):format(kw("if"), kw("rising_edge"), kw("then"))
    )
    push(3, ("%s wr_go %s"):format(kw("if"), kw("then")))
    push(
      4,
      ("%s(%s(%s(%s - 1 %s 0))) <= %s;"):format(
        memory,
        kw("to_integer"),
        wr_bin,
        addr,
        kw("downto"),
        name("wr_data", "input")
      )
    )
    push(3, kw("end if") .. ";")
    push(2, kw("end if") .. ";")
    push(
      1,
      ("%s %s %s;"):format(kw("end"), kw("process"), name("memory", "process"))
    )
    push(0, "")

    push(
      1,
      ("%s : %s (wr_clk, wr_rst_n) %s"):format(
        name("write", "process"),
        kw("process"),
        kw("is")
      )
    )
    push(1, kw("begin"))
    push(2, ("%s wr_rst_n = '0' %s"):format(kw("if"), kw("then")))
    push(3, ("%s <= (%s => '0');"):format(wr_bin, kw("others")))
    push(3, ("%s <= (%s => '0');"):format(wr_gray_r, kw("others")))
    push(
      3,
      ("%s <= (%s => (%s => '0'));"):format(rd_sync, kw("others"), kw("others"))
    )
    push(
      2,
      ("%s %s(wr_clk) %s"):format(kw("elsif"), kw("rising_edge"), kw("then"))
    )
    push(
      3,
      ("%s <= %s & %s(1 %s %s - 1);"):format(
        rd_sync,
        rd_gray_r,
        rd_sync,
        kw("to"),
        stages
      )
    )
    push(3, "")
    push(3, ("%s wr_go %s"):format(kw("if"), kw("then")))
    push(4, ("%s <= %s + 1;"):format(wr_bin, wr_bin))
    push(4, "-- Gray from the incremented binary value, in the same cycle:")
    push(4, "-- the two must never disagree.")
    push(
      4,
      ("%s <= %s((%s + 1) %s ((%s + 1) %s 1));"):format(
        wr_gray_r,
        kw("std_logic_vector"),
        wr_bin,
        kw("xor"),
        wr_bin,
        kw("srl")
      )
    )
    push(3, kw("end if") .. ";")
    push(2, kw("end if") .. ";")
    push(
      1,
      ("%s %s %s;"):format(kw("end"), kw("process"), name("write", "process"))
    )
    push(0, "")

    -- Read domain
    push(1, "-- Read domain.")
    push(
      1,
      ("%s : %s (rd_clk, rd_rst_n) %s"):format(
        name("read", "process"),
        kw("process"),
        kw("is")
      )
    )
    push(1, kw("begin"))
    push(2, ("%s rd_rst_n = '0' %s"):format(kw("if"), kw("then")))
    push(3, ("%s <= (%s => '0');"):format(rd_bin, kw("others")))
    push(3, ("%s <= (%s => '0');"):format(rd_gray_r, kw("others")))
    push(
      3,
      ("%s <= (%s => (%s => '0'));"):format(wr_sync, kw("others"), kw("others"))
    )
    push(
      2,
      ("%s %s(rd_clk) %s"):format(kw("elsif"), kw("rising_edge"), kw("then"))
    )
    push(
      3,
      ("%s <= %s & %s(1 %s %s - 1);"):format(
        wr_sync,
        wr_gray_r,
        wr_sync,
        kw("to"),
        stages
      )
    )
    push(3, "")
    push(3, ("%s rd_go %s"):format(kw("if"), kw("then")))
    push(4, ("%s <= %s + 1;"):format(rd_bin, rd_bin))
    push(
      4,
      ("%s <= %s((%s + 1) %s ((%s + 1) %s 1));"):format(
        rd_gray_r,
        kw("std_logic_vector"),
        rd_bin,
        kw("xor"),
        rd_bin,
        kw("srl")
      )
    )
    push(3, kw("end if") .. ";")
    push(2, kw("end if") .. ";")
    push(
      1,
      ("%s %s %s;"):format(kw("end"), kw("process"), name("read", "process"))
    )
    push(0, "")

    push(1, "-- Asynchronous read: the word is already there, because the")
    push(1, "-- write pointer only reaches this domain after it was written.")
    push(
      1,
      ("%s <= %s(%s(%s(%s - 1 %s 0)));"):format(
        name("rd_data", "output"),
        memory,
        kw("to_integer"),
        rd_bin,
        addr,
        kw("downto")
      )
    )
    push(0, "")

    push(1, "-- Empty when the read pointer has caught the write pointer.")
    push(
      1,
      ("%s <= '1' %s %s = %s(%s) %s '0';"):format(
        empty,
        kw("when"),
        rd_gray_r,
        wr_sync,
        stages,
        kw("else")
      )
    )
    push(0, "")
    push(1, "-- Full when the write pointer has lapped the read pointer: the")
    push(1, "-- same address with the top two bits inverted.")
    -- Built as one string: split across two format calls it was a
    -- placeholder short, which the fixture matrix caught immediately.
    local lapped = {
      ("(%s %s(%s)(%s)) &"):format(kw("not"), rd_sync, stages, addr),
      ("(%s %s(%s)(%s - 1)) &"):format(kw("not"), rd_sync, stages, addr),
      ("%s(%s)(%s - 2 %s 0)"):format(rd_sync, stages, addr, kw("downto")),
    }
    push(1, ("%s <= '1' %s %s = ("):format(full, kw("when"), wr_gray_r))
    for _, term in ipairs(lapped) do
      push(3, term)
    end
    push(2, (") %s '0';"):format(kw("else")))
    push(0, "")
    push(1, ("%s <= %s;"):format(name("full", "output"), full))
    push(1, ("%s <= %s;"):format(name("empty", "output"), empty))
    push(0, "")
    push(0, ("%s %s rtl;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
