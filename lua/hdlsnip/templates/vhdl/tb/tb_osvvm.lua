--- OSVVM testbench.
---
--- Needs an external library, so its fixtures are written where the analysis
--- step does not look. They still diff, which is the other reason fixtures
--- exist.
---
--- What OSVVM gives you over a plain testbench is the alert and log
--- machinery: a count of errors that survives the run, severity levels that
--- can be tuned per test, and a transcript. `AffirmIf` is the check to reach
--- for -- it both counts and reports, where a bare assertion does neither in
--- a way the summary can see.
local style = require("hdlsnip.style")

return {
  name = "tb_osvvm",
  trig = "otb",
  kind = "tb",
  scope = "design_unit",
  desc = "OSVVM testbench with alerts and logs",
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
    push(0, ("%s osvvm;"):format(kw("library")))
    push(1, ("%s osvvm.OsvvmContext;"):format(kw("context")))
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
    push(1, ("%s running : boolean := true;"):format(kw("signal")))
    push(0, "")
    push(0, kw("begin"))
    push(0, "")
    push(1, "-- Stopped by the test process, so the run ends.")
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
      local released = cfg.reset.polarity == "low" and "1" or "0"
      push(
        1,
        ("%s <= '%s' %s 4 * %s;"):format(
          cfg.reset.name,
          released,
          kw("after"),
          period
        )
      )
      push(0, "")
    end

    push(1, ("-- %s : %s work.%s"):format(params.dut, kw("entity"), params.dut))
    push(1, ("--   %s %s ("):format(kw("port"), kw("map")))
    push(1, ("--     %s => %s"):format(cfg.clock.name, cfg.clock.name))
    if has_reset then
      push(1, ("--     , %s => %s"):format(cfg.reset.name, cfg.reset.name))
    end
    push(1, "--   );")
    push(0, "")

    local label = style.name(cfg, "test", "process")
    push(1, ("%s : %s %s"):format(label, kw("process"), kw("is")))
    push(1, kw("begin"))
    push(2, ('SetAlertLogName("%s");'):format(name))
    push(2, "-- A transcript alongside the console, so a failing run leaves")
    push(2, "-- something to read afterwards.")
    push(2, ('TranscriptOpen("%s.log");'):format(name))
    push(2, "SetTranscriptMirror(TRUE);")
    push(0, "")
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
    push(2, "-- AffirmIf counts and reports in one place, which a bare")
    push(2, "-- assertion does in neither way the summary can see.")
    push(2, 'AffirmIf(TRUE, "replace with a real check");')
    push(0, "")
    push(2, "-- The summary is the verdict: it prints the counts and sets")
    push(2, "-- the exit status from them.")
    push(2, "ReportAlerts;")
    push(2, "TranscriptClose;")
    push(2, "running <= false;")
    push(2, kw("wait") .. ";")
    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), label))
    push(0, "")
    push(0, ("%s %s tb;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
