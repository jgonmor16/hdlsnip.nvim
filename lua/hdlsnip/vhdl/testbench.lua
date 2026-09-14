--- Writing a testbench around an entity.
---
--- The testbench template writes the scaffolding -- clock, reset, stop
--- mechanism -- and leaves a commented instantiation for you to fill in. This
--- reads the entity instead, so the DUT arrives wired up and the signals
--- already declared.
---
--- Everything here is composition: the entity parser, the instantiation
--- generator and the same style helpers the templates use. Nothing new is
--- invented, which is why it is short.
local style = require("hdlsnip.style")
local generate = require("hdlsnip.vhdl.generate")

local M = {}

--- Default stimulus for a port, driven from the testbench.
---
--- An input needs a value at time zero or the design starts with 'U' on it
--- and every comparison downstream is meaningless.
---@param port table
---@return string?
local function initial(port)
  if port.mode ~= "in" then
    return nil
  end
  if port.subtype:lower():match("^std_logic$") then
    return "'0'"
  end
  if port.subtype:lower():match("^std_logic_vector") then
    return "(others => '0')"
  end
  if
    port.subtype:lower():match("^unsigned")
    or port.subtype:lower():match("^signed")
  then
    return "(others => '0')"
  end
  if
    port.subtype:lower():match("^natural")
    or port.subtype:lower():match("^integer")
  then
    return "0"
  end
  return nil
end

--- True when a port looks like a clock.
---
--- By shape rather than by the configured name: a crossing has two clocks and
--- neither is called `clk`, and an AXI design calls its clock `aclk`. Getting
--- this wrong means a testbench that reports done at time zero.
---@param port table
---@return boolean
local function is_clock(port)
  if port.mode ~= "in" or not port.subtype:lower():match("^std_logic$") then
    return false
  end
  local name = port.name:lower()
  return name:match("%f[%w_]clk%f[^%w_]") ~= nil
    or name:match("%f[%w_]clock%f[^%w_]") ~= nil
    or name:match("clk$") ~= nil
    or name:match("clock$") ~= nil
end

--- True when a port looks like a reset.
---@param port table
---@return boolean
local function is_reset(port)
  if port.mode ~= "in" or not port.subtype:lower():match("^std_logic$") then
    return false
  end
  local name = port.name:lower()
  return name:match("rst") ~= nil or name:match("reset") ~= nil
end

--- Whether a reset is active low, from its name.
---
--- The trailing `n` is the near-universal convention, and the alternative --
--- assuming the configured polarity -- is wrong for any design that does not
--- follow it.
---@param name string
---@return boolean
local function active_low(name)
  local lowered = name:lower()
  return lowered:match("_n$") ~= nil or lowered:match("n$") ~= nil
end

--- A complete testbench for `parsed`.
---@param parsed table from `hdlsnip.vhdl.entity`
---@param cfg table
---@param opts table? `{ period_ns, library }`
---@return string
function M.build(parsed, cfg, opts)
  opts = opts or {}
  local kw = style.kw(cfg)
  local ind = cfg.indent
  local name = "tb_" .. parsed.name
  local period = style.name(cfg, "CLK_PERIOD", "constant")
  local modern = tonumber(cfg.vhdl_std) >= 2008
  local period_ns = opts.period_ns or 10
  local lines = {}

  local function push(depth, text)
    lines[#lines + 1] = text == "" and "" or (ind:rep(depth) .. text)
  end

  -- Which ports are clocks and resets, so they are driven rather than
  -- declared as ordinary stimulus. There may be more than one of each: a
  -- domain crossing has two of both.
  local clocks, resets = {}, {}
  local is_clock_port, is_reset_port = {}, {}
  for _, port in ipairs(parsed.ports) do
    if is_clock(port) then
      clocks[#clocks + 1] = port.name
      is_clock_port[port.name] = true
    elseif is_reset(port) then
      resets[#resets + 1] = port.name
      is_reset_port[port.name] = true
    end
  end

  push(0, ("%s ieee;"):format(kw("library")))
  push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
  push(1, ("%s ieee.numeric_std.%s;"):format(kw("use"), kw("all")))
  if modern then
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
  push(1, ("%s %s : time := %d ns;"):format(kw("constant"), period, period_ns))
  push(0, "")

  -- Signals for every port, named as the instantiation will map them, with
  -- inputs driven from time zero.
  local values = generate.signal_values(parsed, cfg)
  local generics = generate.generic_values(parsed)
  local rows = {}
  for _, port in ipairs(parsed.ports) do
    local subtype = port.subtype
    for _, generic in ipairs(parsed.generics) do
      local value = generics[generic.name]
      if value and value ~= generic.name then
        subtype = subtype:gsub("%f[%w_]" .. generic.name .. "%f[^%w_]", value)
      end
    end

    local default
    if is_clock_port[port.name] then
      default = " := '0'"
    elseif is_reset_port[port.name] then
      default = (" := '%s'"):format(active_low(port.name) and "0" or "1")
    else
      local value = initial(port)
      default = value and (" := " .. value) or ""
    end

    rows[#rows + 1] =
      { values[port.name], (": %s%s;"):format(subtype, default) }
  end

  for _, line in ipairs(style.align(rows)) do
    push(1, kw("signal") .. " " .. line)
  end

  push(0, "")
  push(1, ("%s running : boolean := true;"):format(kw("signal")))
  push(0, "")
  push(0, kw("begin"))
  push(0, "")

  if #clocks > 0 then
    push(1, "-- Stopped by the stimulus process, so the run ends.")
    if #clocks > 1 then
      push(1, "-- Both run at the same rate here. A crossing is only really")
      push(1, "-- exercised by unrelated rates: change one of these.")
    end
    for _, name in ipairs(clocks) do
      push(
        1,
        ("%s <= %s %s %s %s / 2 %s running %s '0';"):format(
          values[name],
          kw("not"),
          values[name],
          kw("after"),
          period,
          kw("when"),
          kw("else")
        )
      )
    end
    push(0, "")
  end

  for _, name in ipairs(resets) do
    push(
      1,
      ("%s <= '%s' %s 4 * %s;"):format(
        values[name],
        active_low(name) and "1" or "0",
        kw("after"),
        period
      )
    )
  end
  if #resets > 0 then
    push(0, "")
  end

  local instance = generate.instantiate(parsed, cfg, {
    label = "dut",
    library = opts.library or "work",
    values = values,
  })
  for _, line in ipairs(vim.split(instance, "\n")) do
    push(1, line)
  end
  push(0, "")

  local label = style.name(cfg, "stim", "process")
  push(1, ("%s : %s %s"):format(label, kw("process"), kw("is")))
  push(1, kw("begin"))
  if #resets > 0 then
    local name = resets[1]
    push(
      2,
      ("%s %s %s = '%s';"):format(
        kw("wait"),
        kw("until"),
        values[name],
        active_low(name) and "1" or "0"
      )
    )
  end
  if #clocks > 0 then
    local edge = cfg.clock.edge == "falling" and "falling_edge" or "rising_edge"
    push(
      2,
      ("%s %s %s(%s);"):format(
        kw("wait"),
        kw("until"),
        kw(edge),
        values[clocks[1]]
      )
    )
  end
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
    -- No std.env before VHDL-2008. The clock has stopped, so parking here
    -- empties the event queue and the run ends with a zero exit code, which
    -- a failing assertion would not.
    push(2, kw("wait") .. ";")
  end
  push(1, ("%s %s %s;"):format(kw("end"), kw("process"), label))
  push(0, "")
  push(0, ("%s %s tb;"):format(kw("end"), kw("architecture")))

  return table.concat(lines, "\n")
end

return M
