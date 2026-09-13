--- VUnit testbench.
---
--- Marked as needing an external library: VUnit is not on the runtimepath of
--- a plain GHDL install, so its fixtures are written where the analysis step
--- does not look. They still diff, which is the other reason fixtures exist.
---
--- The `runner_cfg` generic and the `test_runner_setup` / `test_runner_cleanup`
--- pair are what VUnit needs to discover and drive the testbench. The
--- `test_suite` loop is what lets one file hold several independent cases,
--- each starting from a fresh reset.
local style = require("hdlsnip.style")

return {
  name = "tb_vunit",
  trig = "vtb",
  kind = "tb",
  scope = "design_unit",
  desc = "VUnit testbench with a test suite",
  dynamic = true,
  external_libraries = true,

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
    local lines = {}

    local function push(d, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(d) .. text)
    end

    push(0, ("%s ieee;"):format(kw("library")))
    push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
    push(1, ("%s ieee.numeric_std.%s;"):format(kw("use"), kw("all")))
    push(0, "")
    push(0, ("%s vunit_lib;"):format(kw("library")))
    push(1, ("%s vunit_lib.vunit_context;"):format(kw("context")))
    push(0, "")
    push(0, ("%s %s %s"):format(kw("entity"), name, kw("is")))
    push(1, ("%s ("):format(kw("generic")))
    push(2, "-- Set by VUnit; do not drive it yourself.")
    push(2, "runner_cfg : string")
    push(1, ");")
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

    local signals =
      { { cfg.clock.name, (": %s := '0';"):format(kw("std_logic")) } }
    if has_reset then
      local idle = cfg.reset.polarity == "low" and "0" or "1"
      signals[#signals + 1] =
        { cfg.reset.name, (": %s := '%s';"):format(kw("std_logic"), idle) }
    end
    for _, line in ipairs(style.align(signals)) do
      push(1, kw("signal") .. " " .. line)
    end

    push(0, "")
    push(0, kw("begin"))
    push(0, "")
    push(1, "-- VUnit stops the run itself, so the clock is free running.")
    push(
      1,
      ("%s <= %s %s %s %s / 2;"):format(
        cfg.clock.name,
        kw("not"),
        cfg.clock.name,
        kw("after"),
        period
      )
    )
    push(0, "")
    push(1, ("-- %s : %s work.%s"):format(params.dut, kw("entity"), params.dut))
    push(1, ("--   %s %s ("):format(kw("port"), kw("map")))
    push(1, ("--     %s => %s"):format(cfg.clock.name, cfg.clock.name))
    if has_reset then
      push(1, ("--     , %s => %s"):format(cfg.reset.name, cfg.reset.name))
    end
    push(1, "--   );")
    push(0, "")

    local label = style.name(cfg, "main", "process")
    push(1, ("%s : %s %s"):format(label, kw("process"), kw("is")))
    push(1, kw("begin"))
    push(2, "test_runner_setup(runner, runner_cfg);")
    push(0, "")
    push(2, "-- Each case starts from a fresh reset, so one failure does")
    push(2, "-- not leave the design in a state that fails the next.")
    push(2, ("%s test_suite %s"):format(kw("while"), kw("loop")))
    if has_reset then
      local asserted = cfg.reset.polarity == "low" and "0" or "1"
      local released = cfg.reset.polarity == "low" and "1" or "0"
      push(3, ("%s <= '%s';"):format(cfg.reset.name, asserted))
      push(3, ("%s %s 4 * %s;"):format(kw("wait"), kw("for"), period))
      push(3, ("%s <= '%s';"):format(cfg.reset.name, released))
      push(
        3,
        ("%s %s %s;"):format(kw("wait"), kw("until"), style.clock_edge(cfg))
      )
      push(3, "")
    end
    push(3, ('%s run("resets cleanly") %s'):format(kw("if"), kw("then")))
    push(4, 'check(true, "replace with a real check");')
    push(0, "")
    push(3, ('%s run("does the thing") %s'):format(kw("elsif"), kw("then")))
    push(4, 'check(true, "replace with a real check");')
    push(3, kw("end if") .. ";")
    push(2, ("%s %s;"):format(kw("end"), kw("loop")))
    push(0, "")
    push(2, "test_runner_cleanup(runner);")
    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), label))
    push(0, "")
    push(1, "-- Fails the run if a test hangs, rather than waiting forever.")
    push(1, "test_runner_watchdog(runner, 1 ms);")
    push(0, "")
    push(0, ("%s %s tb;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
