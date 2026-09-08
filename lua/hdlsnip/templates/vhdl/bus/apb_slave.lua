--- APB slave with a register file.
---
--- Simpler than AXI4-Lite and still common for control registers: one
--- address, one data phase, no outstanding transactions. The two-phase
--- protocol is the part worth generating -- a transfer is only complete when
--- PSEL, PENABLE and PREADY are all high, and acting in the setup phase is
--- the classic mistake.
local style = require("hdlsnip.style")

local function address_width(count)
  local bytes = count * 4
  local bits = 1
  while (2 ^ bits) < bytes do
    bits = bits + 1
  end
  return math.max(bits, 3)
end

return {
  name = "apb_slave",
  trig = "apb",
  kind = "bus",
  scope = "design_unit",
  desc = "APB slave with a register file",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "apb_regs",
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
    local addr_bits = address_width(params.registers)
    local regs = style.name(cfg, "reg_file", "register")
    local index = style.name(cfg, "index", "signal")
    local registers = style.name(cfg, "REGISTERS", "generic")
    local addr_w = style.name(cfg, "ADDR_WIDTH", "generic")
    local prdata = style.name(cfg, "prdata", "register")
    local pslverr = style.name(cfg, "pslverr", "register")
    local lines = {}

    local function push(d, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(d) .. text)
    end

    local slv32 = ("std_logic_vector(31 %s 0)"):format(kw("downto"))
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
    push(2, ("%s : positive := %d"):format(addr_w, addr_bits))
    push(1, ");")

    local ports = { { cfg.clock.name, (": %s"):format(kw("in")), "std_logic" } }
    if has_reset then
      ports[#ports + 1] =
        { cfg.reset.name, (": %s"):format(kw("in")), "std_logic" }
    end
    vim.list_extend(ports, {
      { "paddr", (": %s"):format(kw("in")), slv_addr },
      { "psel", (": %s"):format(kw("in")), "std_logic" },
      { "penable", (": %s"):format(kw("in")), "std_logic" },
      { "pwrite", (": %s"):format(kw("in")), "std_logic" },
      { "pwdata", (": %s"):format(kw("in")), slv32 },
      { "pready", (": %s"):format(kw("out")), "std_logic" },
      { "prdata", (": %s"):format(kw("out")), slv32 },
      { "pslverr", (": %s"):format(kw("out")), "std_logic" },
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
    push(1, ("%s %s : natural;"):format(kw("signal"), index))
    push(1, ("%s %s : %s;"):format(kw("signal"), prdata, slv32))
    push(1, ("%s %s : std_logic;"):format(kw("signal"), pslverr))
    push(0, "")
    push(0, kw("begin"))
    push(0, "")
    push(1, "-- No wait states: the access phase always completes.")
    push(1, "pready <= '1';")
    push(0, "")
    push(
      1,
      ("%s <= %s(%s(paddr(%s - 1 %s 2)));"):format(
        index,
        kw("to_integer"),
        kw("unsigned"),
        addr_w,
        kw("downto")
      )
    )
    push(0, "")

    local label = style.name(cfg, "apb", "process")
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
      push(d, ("%s <= (%s => '0');"):format(prdata, kw("others")))
      push(d, ("%s <= '0';"):format(pslverr))
    end

    local function body(d)
      push(d, "-- A transfer completes only in the access phase, when PSEL")
      push(d, "-- and PENABLE are both high. Acting in the setup phase is")
      push(d, "-- the classic APB mistake.")
      push(
        d,
        ("%s psel = '1' %s penable = '1' %s"):format(
          kw("if"),
          kw("and"),
          kw("then")
        )
      )
      push(
        d + 1,
        ("%s %s < %s %s"):format(kw("if"), index, registers, kw("then"))
      )
      push(d + 2, ("%s <= '0';"):format(pslverr))
      push(d + 2, ("%s pwrite = '1' %s"):format(kw("if"), kw("then")))
      push(d + 3, ("%s(%s) <= pwdata;"):format(regs, index))
      push(d + 2, kw("else"))
      push(d + 3, ("%s <= %s(%s);"):format(prdata, regs, index))
      push(d + 2, kw("end if") .. ";")
      push(d + 1, kw("else"))
      push(d + 2, "-- Outside the register file: report the error rather")
      push(d + 2, "-- than aliasing onto a real register.")
      push(d + 2, ("%s <= '1';"):format(pslverr))
      push(d + 2, ("%s <= (%s => '0');"):format(prdata, kw("others")))
      push(d + 1, kw("end if") .. ";")
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
    push(1, ("prdata  <= %s;"):format(prdata))
    push(1, ("pslverr <= %s;"):format(pslverr))
    push(0, "")
    push(0, ("%s %s rtl;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
