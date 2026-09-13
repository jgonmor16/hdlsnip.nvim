--- Testbench skeleton.
---
--- The clock generator, the reset sequence and the stop mechanism are the
--- three things every testbench needs and nobody enjoys typing. All three
--- depend on configuration or on the VHDL revision, which is why this is
--- generated rather than copied: `std.env.finish` does not exist before
--- VHDL-2008, and a design with no reset must not get a reset process.
local style = require("hdlsnip.style")

return {
  name = "testbench",
  trig = "tb",
  kind = "tb",
  scope = "design_unit",
  desc = "Self-checking testbench skeleton",
  dynamic = true,

  params = {
    {
      name = "dut",
      type = "identifier",
      default = "dut",
      desc = "Entity under test, without the tb_ prefix",
    },
    {
      name = "period_ns",
      type = "integer",
      default = 10,
      min = 1,
      max = 100000,
      desc = "Clock period in nanoseconds",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local name = "tb_" .. params.dut
    local period = style.name(cfg, "CLK_PERIOD", "constant")
    local has_reset = cfg.reset.style ~= "none"
    local modern = tonumber(cfg.vhdl_std) >= 2008
    local lines = {}

    local function push(depth, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(depth) .. text)
    end

    push(0, ("%s ieee;"):format(kw("library")))
    push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
    push(1, ("%s ieee.numeric_std.%s;"):format(kw("use"), kw("all")))

    if modern then
      -- std.env arrived in VHDL-2008. Before that a testbench stops itself
      -- with a failing assertion, which is uglier but portable.
      push(0, "")
      push(0, ("%s std;"):format(kw("library")))
      push(1, ("%s std.env.finish;"):format(kw("use")))
    end

    push(0, "")
    push(0, ("%s %s %s"):format(kw("entity"), name, kw("is")))
    push(0, ("%s %s %s;"):format(kw("end"), kw("entity"), name))
    push(0, "")
    push(
      0,
      ("%s tb %s %s %s"):format(kw("architecture"), kw("of"), name, kw("is"))
    )
    push(0, "")
    push(
      1,
      ("%s %s : time := %d ns;"):format(
        kw("constant"),
        period,
        params.period_ns
      )
    )
    push(0, "")

    local signals = {
      { cfg.clock.name, (": %s := '0';"):format(kw("std_logic")) },
    }
    if has_reset then
      -- Start asserted, so the design is held in reset from time zero.
      local idle = cfg.reset.polarity == "low" and "0" or "1"
      signals[#signals + 1] =
        { cfg.reset.name, (": %s := '%s';"):format(kw("std_logic"), idle) }
    end
    for _, line in ipairs(style.align(signals)) do
      push(1, kw("signal") .. " " .. line)
    end

    push(0, "")
    push(1, ("%s running : boolean := true;"):format(kw("signal")))
    push(0, "")
    push(0, kw("begin"))
    push(0, "")

    -- A free-running clock would keep the simulation alive forever, so it
    -- stops when the stimulus process is done.
    push(1, "-- Clock, stopped by the stimulus process so the run ends.")
    push(
      1,
      ("%s <= %s %s %s %s / 2 %s running %s '0';"):format(
        cfg.clock.name,
        kw("not"),
        cfg.clock.name,
        kw("after"),
        period,
        kw("when"),
        kw("else")
      )
    )
    push(0, "")

    if has_reset then
      local asserted = cfg.reset.polarity == "low" and "0" or "1"
      local released = cfg.reset.polarity == "low" and "1" or "0"
      local label = style.name(cfg, "reset", "process")
      push(1, ("%s : %s %s"):format(label, kw("process"), kw("is")))
      push(1, kw("begin"))
      push(2, ("%s <= '%s';"):format(cfg.reset.name, asserted))
      push(2, ("%s %s 4 * %s;"):format(kw("wait"), kw("for"), period))
      push(2, ("%s <= '%s';"):format(cfg.reset.name, released))
      push(2, kw("wait") .. ";")
      push(1, ("%s %s %s;"):format(kw("end"), kw("process"), label))
      push(0, "")
    end

    push(1, ("-- %s : %s work.%s"):format(params.dut, kw("entity"), params.dut))
    push(1, ("--   %s %s ("):format(kw("port"), kw("map")))
    local ports = { { cfg.clock.name, "=> " .. cfg.clock.name } }
    if has_reset then
      ports[#ports + 1] = { cfg.reset.name, "=> " .. cfg.reset.name }
    end
    local aligned = style.align(ports)
    for index, line in ipairs(aligned) do
      push(1, "--     " .. line .. (index < #aligned and "," or ""))
    end
    push(1, "--   );")
    push(0, "")

    local label = style.name(cfg, "stim", "process")
    push(1, ("%s : %s %s"):format(label, kw("process"), kw("is")))
    push(1, kw("begin"))
    if has_reset then
      local released = cfg.reset.polarity == "low" and "1" or "0"
      push(
        2,
        ("%s %s %s = '%s';"):format(
          kw("wait"),
          kw("until"),
          cfg.reset.name,
          released
        )
      )
    end
    push(
      2,
      ("%s %s %s;"):format(kw("wait"), kw("until"), style.clock_edge(cfg))
    )
    push(0, "")
    push(2, "-- stimulus and checks")
    push(0, "")
    push(
      2,
      ('%s "%s: done" %s %s;'):format(
        kw("report"),
        name,
        kw("severity"),
        kw("note")
      )
    )
    push(2, "running <= false;")
    if modern then
      push(2, "finish;")
    else
      -- Before VHDL-2008 there is no std.env.finish. Stopping with a failing
      -- assertion is the traditional trick, but it exits non-zero and makes a
      -- passing testbench look like a failure in CI. The clock has already
      -- stopped, so parking here empties the event queue and the simulation
      -- ends on its own.
      push(2, kw("wait") .. ";")
    end
    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), label))
    push(0, "")
    push(0, ("%s %s tb;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
