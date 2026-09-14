--- Wishbone B4 classic slave with a register file.
---
--- The classic cycle is the part worth generating: a transfer happens when
--- CYC and STB are both high and the slave answers with ACK, and ACK must be
--- a single cycle or the master counts one transfer as several.
---
--- Classic rather than pipelined: no STALL, one transfer in flight, which is
--- what a control register block wants. A pipelined slave is a different
--- template.
local style = require("hdlsnip.style")

local function address_width(count)
  local bits = 1
  while (2 ^ bits) < count do
    bits = bits + 1
  end
  return math.max(bits, 1)
end

return {
  name = "wishbone_slave",
  trig = "wb",
  kind = "bus",
  scope = "design_unit",
  desc = "Wishbone B4 classic slave with a register file",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "wb_regs",
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
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local has_reset = cfg.reset.style ~= "none"
    local registers = style.name(cfg, "REGISTERS", "generic")
    local addr_w = style.name(cfg, "ADDR_WIDTH", "generic")
    local regs = style.name(cfg, "reg_file", "register")
    local index = style.name(cfg, "index", "signal")
    local ack = style.name(cfg, "ack", "register")
    local dat_o = style.name(cfg, "dat", "register")
    local lines = {}

    local function push(d, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(d) .. text)
    end

    local slv32 = ("std_logic_vector(31 %s 0)"):format(kw("downto"))
    local slv4 = ("std_logic_vector(3 %s 0)"):format(kw("downto"))
    local slv_addr = ("std_logic_vector(%s - 1 %s 0)"):format(
      addr_w,
      kw("downto")
    )

    push(0, ("%s ieee;"):format(kw("library")))
    push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
    push(1, ("%s ieee.numeric_std.%s;"):format(kw("use"), kw("all")))
    push(0, "")
    push(0, ("%s %s %s"):format(kw("entity"), params.name, kw("is")))
    push(1, ("%s ("):format(kw("generic")))
    push(2, ("%s : positive := %d;"):format(registers, params.registers))
    push(
      2,
      ("%s : positive := %d"):format(addr_w, address_width(params.registers))
    )
    push(1, ");")

    local ports = { { cfg.clock.name, (": %s"):format(kw("in")), "std_logic" } }
    if has_reset then
      ports[#ports + 1] =
        { cfg.reset.name, (": %s"):format(kw("in")), "std_logic" }
    end
    vim.list_extend(ports, {
      { "wb_cyc_i", (": %s"):format(kw("in")), "std_logic" },
      { "wb_stb_i", (": %s"):format(kw("in")), "std_logic" },
      { "wb_we_i", (": %s"):format(kw("in")), "std_logic" },
      { "wb_adr_i", (": %s"):format(kw("in")), slv_addr },
      { "wb_dat_i", (": %s"):format(kw("in")), slv32 },
      { "wb_sel_i", (": %s"):format(kw("in")), slv4 },
      { "wb_dat_o", (": %s"):format(kw("out")), slv32 },
      { "wb_ack_o", (": %s"):format(kw("out")), "std_logic" },
      { "wb_err_o", (": %s"):format(kw("out")), "std_logic" },
    })
    push(1, ("%s ("):format(kw("port")))
    local aligned = style.align(ports)
    for i, line in ipairs(aligned) do
      push(2, line .. (i < #aligned and ";" or ""))
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
      ("%s t_registers %s %s (natural %s 0 %s %s - 1) %s %s;"):format(
        kw("type"),
        kw("is"),
        kw("array"),
        kw("range"),
        kw("to"),
        registers,
        kw("of"),
        slv32
      )
    )
    push(0, "")
    push(1, ("%s %s : t_registers;"):format(kw("signal"), regs))
    push(1, ("%s %s : natural;"):format(kw("signal"), index))
    push(1, ("%s %s : std_logic;"):format(kw("signal"), ack))
    push(1, ("%s %s : %s;"):format(kw("signal"), dat_o, slv32))
    push(
      1,
      ("%s %s : std_logic;"):format(
        kw("signal"),
        style.name(cfg, "err", "register")
      )
    )
    push(0, "")
    push(0, kw("begin"))
    push(0, "")
    push(
      1,
      ("%s <= %s(%s(wb_adr_i));"):format(
        index,
        kw("to_integer"),
        kw("unsigned")
      )
    )
    push(0, "")

    local err = style.name(cfg, "err", "register")
    local label = style.name(cfg, "wishbone", "process")
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

    local function reset_state(d)
      push(
        d,
        ("%s <= (%s => (%s => '0'));"):format(regs, kw("others"), kw("others"))
      )
      push(d, ("%s <= '0';"):format(ack))
      push(d, ("%s <= '0';"):format(err))
      push(d, ("%s <= (%s => '0');"):format(dat_o, kw("others")))
    end

    local function body(d)
      push(d, "-- ACK is a single cycle: held high the master would count")
      push(d, "-- one transfer as several.")
      push(d, ("%s <= '0';"):format(ack))
      push(d, ("%s <= '0';"):format(err))
      push(d, "")
      push(
        d,
        ("%s wb_cyc_i = '1' %s wb_stb_i = '1' %s %s = '0' %s"):format(
          kw("if"),
          kw("and"),
          kw("and"),
          ack,
          kw("then")
        )
      )
      push(
        d + 1,
        ("%s %s < %s %s"):format(kw("if"), index, registers, kw("then"))
      )
      push(d + 2, ("%s wb_we_i = '1' %s"):format(kw("if"), kw("then")))
      push(
        d + 3,
        ("%s byte %s 0 %s 3 %s"):format(
          kw("for"),
          kw("in"),
          kw("to"),
          kw("loop")
        )
      )
      push(d + 4, ("%s wb_sel_i(byte) = '1' %s"):format(kw("if"), kw("then")))
      push(
        d + 5,
        ("%s(%s)(byte * 8 + 7 %s byte * 8) <="):format(
          regs,
          index,
          kw("downto")
        )
      )
      push(d + 6, ("wb_dat_i(byte * 8 + 7 %s byte * 8);"):format(kw("downto")))
      push(d + 4, kw("end if") .. ";")
      push(d + 3, ("%s %s;"):format(kw("end"), kw("loop")))
      push(d + 2, kw("else"))
      push(d + 3, ("%s <= %s(%s);"):format(dat_o, regs, index))
      push(d + 2, kw("end if") .. ";")
      push(d + 1, kw("else"))
      push(d + 2, "-- Outside the register file: ERR rather than a silent")
      push(d + 2, "-- alias onto a real register.")
      push(d + 2, ("%s <= '1';"):format(err))
      push(d + 2, ("%s <= (%s => '0');"):format(dat_o, kw("others")))
      push(d + 1, kw("end if") .. ";")
      push(d + 1, "")
      push(d + 1, ("%s <= '1';"):format(ack))
      push(d, kw("end if") .. ";")
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

    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), label))
    push(0, "")
    push(1, ("wb_ack_o <= %s;"):format(ack))
    push(1, ("wb_err_o <= %s;"):format(err))
    push(1, ("wb_dat_o <= %s;"):format(dat_o))
    push(0, "")
    push(0, ("%s %s rtl;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
