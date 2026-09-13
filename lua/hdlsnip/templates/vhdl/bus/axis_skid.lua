--- AXI-Stream register slice, with a skid buffer.
---
--- Registering an AXI-Stream interface is where backpressure goes wrong. A
--- plain register on the data path breaks the protocol, because `tready` from
--- downstream arrives a cycle late and a word already accepted has nowhere to
--- go. The skid buffer is the one extra register that holds that word.
---
--- The rule this preserves: once `tvalid` is high it must stay high, and the
--- payload must not change, until `tready` is seen. Dropping a word because
--- downstream stalled is the bug this exists to prevent.
local style = require("hdlsnip.style")

return {
  name = "axis_skid",
  trig = "axis",
  kind = "bus",
  scope = "design_unit",
  desc = "AXI-Stream register slice with backpressure",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "axis_skid",
      desc = "Entity name",
    },
    {
      name = "width",
      type = "integer",
      default = 32,
      min = 1,
      max = 4096,
      desc = "Default TDATA width in bits",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local has_reset = cfg.reset.style ~= "none"
    local width = style.name(cfg, "TDATA_WIDTH", "generic")
    local lines = {}

    local function push(d, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(d) .. text)
    end
    local function name(base, kind)
      return style.name(cfg, base, kind)
    end

    local slv = ("std_logic_vector(%s - 1 %s 0)"):format(width, kw("downto"))
    local skid_data = style.name(cfg, "skid_data", "register")
    local skid_last = style.name(cfg, "skid_last", "register")
    local skid_full = style.name(cfg, "skid_full", "register")
    local m_data = style.name(cfg, "m_data", "register")
    local m_last = style.name(cfg, "m_last", "register")
    local m_valid = style.name(cfg, "m_valid", "register")

    push(0, ("%s ieee;"):format(kw("library")))
    push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
    push(0, "")
    push(0, ("%s %s %s"):format(kw("entity"), params.name, kw("is")))
    push(1, ("%s ("):format(kw("generic")))
    push(2, ("%s : positive := %d"):format(width, params.width))
    push(1, ");")

    local ports = { { cfg.clock.name, (": %s"):format(kw("in")), "std_logic" } }
    if has_reset then
      ports[#ports + 1] =
        { cfg.reset.name, (": %s"):format(kw("in")), "std_logic" }
    end
    vim.list_extend(ports, {
      { "s_tdata", (": %s"):format(kw("in")), slv },
      { "s_tlast", (": %s"):format(kw("in")), "std_logic" },
      { "s_tvalid", (": %s"):format(kw("in")), "std_logic" },
      { "s_tready", (": %s"):format(kw("out")), "std_logic" },
      { "m_tdata", (": %s"):format(kw("out")), slv },
      { "m_tlast", (": %s"):format(kw("out")), "std_logic" },
      { "m_tvalid", (": %s"):format(kw("out")), "std_logic" },
      { "m_tready", (": %s"):format(kw("in")), "std_logic" },
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
    push(1, "-- Output register.")
    push(1, ("%s %s : %s;"):format(kw("signal"), m_data, slv))
    push(1, ("%s %s : std_logic;"):format(kw("signal"), m_last))
    push(1, ("%s %s : std_logic := '0';"):format(kw("signal"), m_valid))
    push(0, "")
    push(1, "-- Skid register: holds the word accepted in the cycle the")
    push(1, "-- downstream stall arrived, which would otherwise be lost.")
    push(1, ("%s %s : %s;"):format(kw("signal"), skid_data, slv))
    push(1, ("%s %s : std_logic;"):format(kw("signal"), skid_last))
    push(1, ("%s %s : std_logic := '0';"):format(kw("signal"), skid_full))
    push(0, "")
    push(0, kw("begin"))
    push(0, "")
    push(1, "-- Accept while the skid register is empty.")
    push(1, ("s_tready <= %s %s;"):format(kw("not"), skid_full))
    push(0, "")

    local label = name("skid", "process")
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
      push(d, ("%s <= '0';"):format(m_valid))
      push(d, ("%s <= '0';"):format(skid_full))
    end

    local function body(d)
      push(d, "-- The output register is free when it is empty, or when")
      push(d, "-- downstream took the word this cycle.")
      push(
        d,
        ("%s %s = '0' %s m_tready = '1' %s"):format(
          kw("if"),
          m_valid,
          kw("or"),
          kw("then")
        )
      )
      push(d + 1, ("%s %s = '1' %s"):format(kw("if"), skid_full, kw("then")))
      push(d + 2, ("%s <= %s;"):format(m_data, skid_data))
      push(d + 2, ("%s <= %s;"):format(m_last, skid_last))
      push(d + 2, ("%s <= '1';"):format(m_valid))
      push(d + 2, ("%s <= '0';"):format(skid_full))
      push(
        d + 1,
        ("%s s_tvalid = '1' %s %s = '0' %s"):format(
          kw("elsif"),
          kw("and"),
          skid_full,
          kw("then")
        )
      )
      push(d + 2, ("%s <= s_tdata;"):format(m_data))
      push(d + 2, ("%s <= s_tlast;"):format(m_last))
      push(d + 2, ("%s <= '1';"):format(m_valid))
      push(d + 1, kw("else"))
      push(d + 2, ("%s <= '0';"):format(m_valid))
      push(d + 1, kw("end if") .. ";")
      push(
        d,
        ("%s s_tvalid = '1' %s %s = '0' %s"):format(
          kw("elsif"),
          kw("and"),
          skid_full,
          kw("then")
        )
      )
      push(d + 1, "-- Downstream is stalled and the output is occupied, so")
      push(d + 1, "-- this word goes to the skid register rather than away.")
      push(d + 1, ("%s <= s_tdata;"):format(skid_data))
      push(d + 1, ("%s <= s_tlast;"):format(skid_last))
      push(d + 1, ("%s <= '1';"):format(skid_full))
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
    push(1, ("m_tdata  <= %s;"):format(m_data))
    push(1, ("m_tlast  <= %s;"):format(m_last))
    push(1, ("m_tvalid <= %s;"):format(m_valid))
    push(0, "")
    push(0, ("%s %s rtl;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
