--- AXI4-Lite slave with a register file.
---
--- The template most worth generating: the handshake rules are easy to state
--- and easy to get subtly wrong, and the register decode changes with the
--- register count. Vendor wizards emit this too, but as Verilog-flavoured
--- boilerplate nobody reads.
---
--- Protocol decisions worth knowing about, since they are the ones reviewers
--- ask about:
---
---   * A write is accepted only when both AWVALID and WVALID are high, so the
---     channels cannot be accepted out of step and the response cannot be
---     issued before the data arrives.
---   * READY is asserted for exactly one cycle. The payload is sampled the
---     cycle before, which is safe because AXI requires a master to hold
---     VALID and its payload stable until it sees READY.
---   * A response is not issued while an earlier one is outstanding, so B and
---     R never overrun a slow master.
---   * An address outside the register file answers DECERR rather than
---     silently aliasing, which is what makes a bad address visible.
---   * WSTRB is honoured per byte lane. Ignoring it corrupts a
---     read-modify-write from software.
---
--- The handshake reads back what it drives, and reading an `out` port is
--- illegal before VHDL-2008. Every driven output therefore has an internal
--- signal, wired to the port at the end. That costs nothing in hardware and
--- keeps one body of code valid under every revision.
local style = require("hdlsnip.style")

--- Address bits needed to cover `count` 32-bit registers, byte addressed.
---@param count integer
---@return integer
local function address_width(count)
  local bytes = count * 4
  local bits = 1
  while (2 ^ bits) < bytes do
    bits = bits + 1
  end
  return math.max(bits, 3)
end

return {
  name = "axi4lite_slave",
  trig = "axil",
  kind = "bus",
  scope = "design_unit",
  desc = "AXI4-Lite slave with a register file",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "axi_regs",
      desc = "Entity name",
    },
    {
      name = "registers",
      type = "integer",
      default = 4,
      min = 1,
      max = 256,
      desc = "Number of 32-bit registers",
    },
    {
      name = "prefix",
      type = "string",
      default = "s_axi",
      example = "ctrl",
      desc = "AXI port prefix",
      check = function(value)
        if not value:match("^%a[%w_]*$") then
          return false, "must be an identifier fragment"
        end
        return true
      end,
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local has_reset = cfg.reset.style ~= "none"
    local addr_bits = address_width(params.registers)
    local lines = {}

    local function push(depth, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(depth) .. text)
    end

    local function axi(signal)
      return ("%s_%s"):format(params.prefix, signal)
    end

    local regs = style.name(cfg, "reg_file", "register")
    local wr_index = style.name(cfg, "wr_index", "signal")
    local rd_index = style.name(cfg, "rd_index", "signal")

    --- Internal driver for an output port. Reading an `out` port is illegal
    --- before VHDL-2008, and the handshake reads back what it drives.
    local driven = {
      awready = true,
      wready = true,
      bresp = true,
      bvalid = true,
      arready = true,
      rdata = true,
      rresp = true,
      rvalid = true,
    }
    local function sig(signal)
      if driven[signal] then
        return ("%s_%s_r"):format(params.prefix, signal)
      end
      return ("%s_%s"):format(params.prefix, signal)
    end

    push(0, ("%s ieee;"):format(kw("library")))
    push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
    push(1, ("%s ieee.numeric_std.%s;"):format(kw("use"), kw("all")))
    push(0, "")
    push(0, ("%s %s %s"):format(kw("entity"), params.name, kw("is")))
    push(1, ("%s ("):format(kw("generic")))
    push(
      2,
      ("%s : positive := %d;"):format(
        style.name(cfg, "REGISTERS", "generic"),
        params.registers
      )
    )
    push(
      2,
      ("%s : positive := %d"):format(
        style.name(cfg, "ADDR_WIDTH", "generic"),
        addr_bits
      )
    )
    push(1, ");")

    local addr_w = style.name(cfg, "ADDR_WIDTH", "generic")
    local slv_addr = ("std_logic_vector(%s - 1 %s 0)"):format(
      addr_w,
      kw("downto")
    )
    local slv32 = ("std_logic_vector(31 %s 0)"):format(kw("downto"))
    local slv4 = ("std_logic_vector(3 %s 0)"):format(kw("downto"))
    local slv2 = ("std_logic_vector(1 %s 0)"):format(kw("downto"))

    local ports = { { cfg.clock.name, (": %s"):format(kw("in")), "std_logic" } }
    if has_reset then
      ports[#ports + 1] =
        { cfg.reset.name, (": %s"):format(kw("in")), "std_logic" }
    end
    vim.list_extend(ports, {
      { axi("awaddr"), (": %s"):format(kw("in")), slv_addr },
      { axi("awvalid"), (": %s"):format(kw("in")), "std_logic" },
      { axi("awready"), (": %s"):format(kw("out")), "std_logic" },
      { axi("wdata"), (": %s"):format(kw("in")), slv32 },
      { axi("wstrb"), (": %s"):format(kw("in")), slv4 },
      { axi("wvalid"), (": %s"):format(kw("in")), "std_logic" },
      { axi("wready"), (": %s"):format(kw("out")), "std_logic" },
      { axi("bresp"), (": %s"):format(kw("out")), slv2 },
      { axi("bvalid"), (": %s"):format(kw("out")), "std_logic" },
      { axi("bready"), (": %s"):format(kw("in")), "std_logic" },
      { axi("araddr"), (": %s"):format(kw("in")), slv_addr },
      { axi("arvalid"), (": %s"):format(kw("in")), "std_logic" },
      { axi("arready"), (": %s"):format(kw("out")), "std_logic" },
      { axi("rdata"), (": %s"):format(kw("out")), slv32 },
      { axi("rresp"), (": %s"):format(kw("out")), slv2 },
      { axi("rvalid"), (": %s"):format(kw("out")), "std_logic" },
      { axi("rready"), (": %s"):format(kw("in")), "std_logic" },
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
    local registers = style.name(cfg, "REGISTERS", "generic")
    push(
      1,
      ("%s t_registers %s %s (0 %s %s - 1) %s %s;"):format(
        kw("type"),
        kw("is"),
        kw("array"),
        kw("to"),
        registers,
        kw("of"),
        slv32
      )
    )
    push(0, "")
    push(1, ("%s %s : t_registers;"):format(kw("signal"), regs))
    push(0, "")
    push(1, "-- Word index, so the two low address bits are dropped.")
    push(1, ("%s %s : natural;"):format(kw("signal"), wr_index))
    push(1, ("%s %s : natural;"):format(kw("signal"), rd_index))
    push(0, "")
    push(1, "-- Internal drivers: the handshake reads back what it drives,")
    push(1, "-- and reading an out port is illegal before VHDL-2008.")
    local drivers = style.align({
      { sig("awready"), ": std_logic;" },
      { sig("wready"), ": std_logic;" },
      { sig("bresp"), (": %s;"):format(slv2) },
      { sig("bvalid"), ": std_logic;" },
      { sig("arready"), ": std_logic;" },
      { sig("rdata"), (": %s;"):format(slv32) },
      { sig("rresp"), (": %s;"):format(slv2) },
      { sig("rvalid"), ": std_logic;" },
    })
    for _, line in ipairs(drivers) do
      push(1, kw("signal") .. " " .. line)
    end
    push(0, "")
    push(0, kw("begin"))
    push(0, "")

    push(
      1,
      ("%s <= %s(%s(%s(%s - 1 %s 2)));"):format(
        wr_index,
        kw("to_integer"),
        kw("unsigned"),
        axi("awaddr"),
        addr_w,
        kw("downto")
      )
    )
    push(
      1,
      ("%s <= %s(%s(%s(%s - 1 %s 2)));"):format(
        rd_index,
        kw("to_integer"),
        kw("unsigned"),
        axi("araddr"),
        addr_w,
        kw("downto")
      )
    )
    push(0, "")

    -- ---------------------------------------------------------------------
    -- Write
    -- ---------------------------------------------------------------------
    local write_label = style.name(cfg, "write", "process")
    push(
      1,
      ("%s : %s %s %s"):format(
        write_label,
        kw("process"),
        style.sensitivity(cfg),
        kw("is")
      )
    )
    push(1, kw("begin"))

    local function write_reset(depth)
      push(depth, ("%s <= '0';"):format(sig("awready")))
      push(depth, ("%s <= '0';"):format(sig("wready")))
      push(depth, ("%s <= '0';"):format(sig("bvalid")))
      push(depth, ('%s <= "00";'):format(sig("bresp")))
      push(
        depth,
        ("%s <= (%s => (%s => '0'));"):format(regs, kw("others"), kw("others"))
      )
    end

    local function write_body(depth)
      push(depth, "-- READY is a single cycle pulse.")
      push(depth, ("%s <= '0';"):format(sig("awready")))
      push(depth, ("%s <= '0';"):format(sig("wready")))
      push(depth, "")
      push(
        depth,
        ("%s %s = '1' %s %s = '1' %s"):format(
          kw("if"),
          sig("bvalid"),
          kw("and"),
          axi("bready"),
          kw("then")
        )
      )
      push(depth + 1, ("%s <= '0';"):format(sig("bvalid")))
      push(depth, kw("end if") .. ";")
      push(depth, "")
      push(depth, "-- Both channels must be valid, so a response is never")
      push(depth, "-- issued before the data arrives, and no new response is")
      push(depth, "-- started while an earlier one is outstanding.")
      push(
        depth,
        ("%s %s = '1' %s %s = '1'"):format(
          kw("if"),
          axi("awvalid"),
          kw("and"),
          axi("wvalid")
        )
      )
      push(
        depth + 2,
        ("%s %s = '0' %s %s = '0'"):format(
          kw("and"),
          sig("awready"),
          kw("and"),
          sig("wready")
        )
      )
      push(
        depth + 2,
        ("%s (%s = '0' %s %s = '1') %s"):format(
          kw("and"),
          sig("bvalid"),
          kw("or"),
          axi("bready"),
          kw("then")
        )
      )
      push(depth + 1, ("%s <= '1';"):format(sig("awready")))
      push(depth + 1, ("%s <= '1';"):format(sig("wready")))
      push(depth + 1, "")
      push(
        depth + 1,
        ("%s %s < %s %s"):format(kw("if"), wr_index, registers, kw("then"))
      )
      push(depth + 2, "-- Byte strobes: ignoring them corrupts a")
      push(depth + 2, "-- read-modify-write from software.")
      push(
        depth + 2,
        ("%s byte %s 0 %s 3 %s"):format(
          kw("for"),
          kw("in"),
          kw("to"),
          kw("loop")
        )
      )
      push(
        depth + 3,
        ("%s %s(byte) = '1' %s"):format(kw("if"), axi("wstrb"), kw("then"))
      )
      push(
        depth + 4,
        ("%s(%s)(byte * 8 + 7 %s byte * 8) <="):format(
          regs,
          wr_index,
          kw("downto")
        )
      )
      push(
        depth + 5,
        ("%s(byte * 8 + 7 %s byte * 8);"):format(axi("wdata"), kw("downto"))
      )
      push(depth + 3, kw("end if") .. ";")
      push(depth + 2, ("%s %s;"):format(kw("end"), kw("loop")))
      push(depth + 2, ('%s <= "00";'):format(sig("bresp")))
      push(depth + 1, kw("else"))
      push(depth + 2, "-- Outside the register file: DECERR rather than a")
      push(depth + 2, "-- silent alias, so a bad address is visible.")
      push(depth + 2, ('%s <= "11";'):format(sig("bresp")))
      push(depth + 1, kw("end if") .. ";")
      push(depth + 1, "")
      push(depth + 1, ("%s <= '1';"):format(sig("bvalid")))
      push(depth, kw("end if") .. ";")
    end

    if cfg.reset.style == "async" then
      push(
        2,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      write_reset(3)
      push(
        2,
        ("%s %s %s"):format(kw("elsif"), style.clock_edge(cfg), kw("then"))
      )
      write_body(3)
      push(2, kw("end if") .. ";")
    elseif cfg.reset.style == "sync" then
      push(2, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      push(
        3,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      write_reset(4)
      push(3, kw("else"))
      write_body(4)
      push(3, kw("end if") .. ";")
      push(2, kw("end if") .. ";")
    else
      push(2, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      write_body(3)
      push(2, kw("end if") .. ";")
    end

    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), write_label))
    push(0, "")

    -- ---------------------------------------------------------------------
    -- Read
    -- ---------------------------------------------------------------------
    local read_label = style.name(cfg, "read", "process")
    push(
      1,
      ("%s : %s %s %s"):format(
        read_label,
        kw("process"),
        style.sensitivity(cfg),
        kw("is")
      )
    )
    push(1, kw("begin"))

    local function read_reset(depth)
      push(depth, ("%s <= '0';"):format(sig("arready")))
      push(depth, ("%s <= '0';"):format(sig("rvalid")))
      push(depth, ('%s <= "00";'):format(sig("rresp")))
      push(depth, ("%s <= (%s => '0');"):format(sig("rdata"), kw("others")))
    end

    local function read_body(depth)
      push(depth, ("%s <= '0';"):format(sig("arready")))
      push(depth, "")
      push(
        depth,
        ("%s %s = '1' %s %s = '1' %s"):format(
          kw("if"),
          sig("rvalid"),
          kw("and"),
          axi("rready"),
          kw("then")
        )
      )
      push(depth + 1, ("%s <= '0';"):format(sig("rvalid")))
      push(depth, kw("end if") .. ";")
      push(depth, "")
      push(
        depth,
        ("%s %s = '1' %s %s = '0'"):format(
          kw("if"),
          axi("arvalid"),
          kw("and"),
          sig("arready")
        )
      )
      push(
        depth + 2,
        ("%s (%s = '0' %s %s = '1') %s"):format(
          kw("and"),
          sig("rvalid"),
          kw("or"),
          axi("rready"),
          kw("then")
        )
      )
      push(depth + 1, ("%s <= '1';"):format(sig("arready")))
      push(depth + 1, "")
      push(
        depth + 1,
        ("%s %s < %s %s"):format(kw("if"), rd_index, registers, kw("then"))
      )
      push(depth + 2, ("%s <= %s(%s);"):format(sig("rdata"), regs, rd_index))
      push(depth + 2, ('%s <= "00";'):format(sig("rresp")))
      push(depth + 1, kw("else"))
      push(depth + 2, ("%s <= (%s => '0');"):format(sig("rdata"), kw("others")))
      push(depth + 2, ('%s <= "11";'):format(sig("rresp")))
      push(depth + 1, kw("end if") .. ";")
      push(depth + 1, "")
      push(depth + 1, ("%s <= '1';"):format(sig("rvalid")))
      push(depth, kw("end if") .. ";")
    end

    if cfg.reset.style == "async" then
      push(
        2,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      read_reset(3)
      push(
        2,
        ("%s %s %s"):format(kw("elsif"), style.clock_edge(cfg), kw("then"))
      )
      read_body(3)
      push(2, kw("end if") .. ";")
    elseif cfg.reset.style == "sync" then
      push(2, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      push(
        3,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      read_reset(4)
      push(3, kw("else"))
      read_body(4)
      push(3, kw("end if") .. ";")
      push(2, kw("end if") .. ";")
    else
      push(2, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      read_body(3)
      push(2, kw("end if") .. ";")
    end

    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), read_label))
    push(0, "")

    local wiring = {}
    for _, signal in ipairs({
      "awready",
      "wready",
      "bresp",
      "bvalid",
      "arready",
      "rdata",
      "rresp",
      "rvalid",
    }) do
      wiring[#wiring + 1] = { axi(signal), "<= " .. sig(signal) .. ";" }
    end
    for _, line in ipairs(style.align(wiring)) do
      push(1, line)
    end

    push(0, "")
    push(0, ("%s %s rtl;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
