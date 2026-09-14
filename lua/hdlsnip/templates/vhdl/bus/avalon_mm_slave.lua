--- Avalon-MM slave with a register file.
---
--- The wait state is the part worth generating. A slave with fixed read
--- latency answers a read that many cycles later with no handshake at all,
--- and getting the declared latency and the actual one out of step is a bug
--- the interconnect will not catch.
---
--- This uses waitrequest with zero read latency instead: the transfer
--- completes in the cycle waitrequest is low, which is the simpler contract
--- and needs no latency declaration to keep in sync.
local style = require("hdlsnip.style")

local function address_width(count)
  local bits = 1
  while (2 ^ bits) < count do
    bits = bits + 1
  end
  return math.max(bits, 1)
end

return {
  name = "avalon_mm_slave",
  trig = "avmm",
  kind = "bus",
  scope = "design_unit",
  desc = "Avalon-MM slave with a register file",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "avmm_regs",
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
    local rdata = style.name(cfg, "readdata", "register")
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
      { "avs_address", (": %s"):format(kw("in")), slv_addr },
      { "avs_read", (": %s"):format(kw("in")), "std_logic" },
      { "avs_write", (": %s"):format(kw("in")), "std_logic" },
      { "avs_writedata", (": %s"):format(kw("in")), slv32 },
      { "avs_byteenable", (": %s"):format(kw("in")), slv4 },
      { "avs_readdata", (": %s"):format(kw("out")), slv32 },
      { "avs_waitrequest", (": %s"):format(kw("out")), "std_logic" },
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
    push(1, ("%s %s : %s;"):format(kw("signal"), rdata, slv32))
    push(0, "")
    push(0, kw("begin"))
    push(0, "")
    push(1, "-- Zero wait states: the transfer completes in the cycle it is")
    push(1, "-- presented, so no read latency has to be kept in step.")
    push(1, "avs_waitrequest <= '0';")
    push(0, "")
    push(
      1,
      ("%s <= %s(%s(avs_address));"):format(
        index,
        kw("to_integer"),
        kw("unsigned")
      )
    )
    push(0, "")

    local label = style.name(cfg, "avalon", "process")
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
      push(d, ("%s <= (%s => '0');"):format(rdata, kw("others")))
    end

    local function body(d)
      push(d, ("%s avs_write = '1' %s"):format(kw("if"), kw("then")))
      push(
        d + 1,
        ("%s %s < %s %s"):format(kw("if"), index, registers, kw("then"))
      )
      push(d + 2, "-- Byte enables: ignoring them corrupts a read modify")
      push(d + 2, "-- write from software.")
      push(
        d + 2,
        ("%s byte %s 0 %s 3 %s"):format(
          kw("for"),
          kw("in"),
          kw("to"),
          kw("loop")
        )
      )
      push(
        d + 3,
        ("%s avs_byteenable(byte) = '1' %s"):format(kw("if"), kw("then"))
      )
      push(
        d + 4,
        ("%s(%s)(byte * 8 + 7 %s byte * 8) <="):format(
          regs,
          index,
          kw("downto")
        )
      )
      push(
        d + 5,
        ("avs_writedata(byte * 8 + 7 %s byte * 8);"):format(kw("downto"))
      )
      push(d + 3, kw("end if") .. ";")
      push(d + 2, ("%s %s;"):format(kw("end"), kw("loop")))
      push(d + 1, kw("end if") .. ";")
      push(d, kw("end if") .. ";")
      push(d, "")
      push(d, ("%s avs_read = '1' %s"):format(kw("if"), kw("then")))
      push(
        d + 1,
        ("%s %s < %s %s"):format(kw("if"), index, registers, kw("then"))
      )
      push(d + 2, ("%s <= %s(%s);"):format(rdata, regs, index))
      push(d + 1, kw("else"))
      push(d + 2, "-- Avalon-MM has no error response, so an unmapped read")
      push(d + 2, "-- returns zero rather than whatever was last there.")
      push(d + 2, ("%s <= (%s => '0');"):format(rdata, kw("others")))
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
    push(1, ("avs_readdata <= %s;"):format(rdata))
    push(0, "")
    push(0, ("%s %s rtl;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
