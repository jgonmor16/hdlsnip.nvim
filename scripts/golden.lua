--- Render every template across a matrix into VHDL files.
---
--- The output is committed. That makes a change to generated RTL show up as
--- a reviewable diff in a pull request instead of hiding inside a Lua change,
--- and it gives GHDL and VSG something concrete to analyse: a template is
--- only correct if what it emits compiles.
---
--- The matrix is one-factor-at-a-time rather than a full cross product. Each
--- case starts from the defaults and changes a single parameter, which covers
--- every parameter and every alternative of a choice without the file count
--- exploding. Configuration variants are crossed with that, because
--- configuration is what most often breaks a template: a reset that is not
--- there, a longer clock name that shifts the alignment, upper case
--- keywords.
---
--- Usage: make golden
local registry = require("hdlsnip.registry")
local render = require("hdlsnip.render")
local config = require("hdlsnip.config")
local template = require("hdlsnip.template")
local style = require("hdlsnip.style")

local OUT = vim.env.HDLSNIP_GOLDEN_DIR or "tests/golden"

--- Configuration variants every template is rendered under.
local VARIANTS = {
  { name = "default", cfg = {} },
  {
    name = "upper_sync_high",
    cfg = {
      keyword_case = "upper",
      reset = { style = "sync", polarity = "high" },
    },
  },
  { name = "no_reset", cfg = { reset = { style = "none" } } },
  -- The revision changes what a template may emit: std.env.finish does not
  -- exist before VHDL-2008.
  { name = "vhdl93", cfg = { vhdl_std = "93" } },
  -- Vendor attributes are a whole code path of their own, and the reason
  -- some templates are generated rather than copied.
  { name = "amd", cfg = { vendor = "amd" } },
  { name = "intel", cfg = { vendor = "intel" } },
  {
    name = "long_names",
    cfg = {
      clock = { name = "axi_aclk" },
      reset = { name = "axi_aresetn" },
      naming = { sig_prefix = "s_" },
    },
  },
}

--- A safe alternative value for a parameter, used to vary one factor.
---@param param table
---@return any[] alternatives
local function alternatives(param)
  if param.type == "boolean" then
    return { not param.default }
  end
  if param.type == "choice" then
    local out = {}
    for _, choice in ipairs(param.choices) do
      if choice ~= param.default then
        out[#out + 1] = choice
      end
    end
    return out
  end
  if param.type == "integer" or param.type == "number" then
    local out = {}
    if param.min and param.min ~= param.default then
      out[#out + 1] = param.min
    end
    if param.max and param.max ~= param.default then
      out[#out + 1] = param.max
    end
    return out
  end
  -- A parameter with a validator knows what a legal alternative looks like
  -- better than this does, so it may name one.
  if param.example then
    return { param.example }
  end
  -- Identifiers and free strings: something legal and obviously generated.
  return { "gold_" .. param.name }
end

---@param tpl table
---@return table[] cases each `{ label = string, params = table }`
local function param_cases(tpl)
  local cases = { { label = "defaults", params = {} } }
  for _, param in ipairs(tpl.params or {}) do
    for _, value in ipairs(alternatives(param)) do
      local slug = tostring(value):gsub("%W", "_")
      cases[#cases + 1] = {
        label = ("%s_%s"):format(param.name, slug),
        params = { [param.name] = value },
      }
    end
  end
  return cases
end

--- Wrap a fragment in enough VHDL to be analysable.
---
--- Most templates are not design files: a clocked process has to sit inside
--- an architecture, with a clock and reset in scope, before GHDL will look at
--- it. The wrapper is generated from the same configuration as the fragment,
--- so the signal names line up with whatever the fragment refers to.
---@param tpl table
---@param cfg table
---@param body string[]
---@return string[]
local function wrap(tpl, cfg, sections, params)
  local scope = template.scope(tpl)
  local body = render.lines(sections.statements or "")
  if scope == "design_unit" then
    return body
  end

  local ind = cfg.indent
  local out = {
    "library ieee;",
    ind .. "use ieee.std_logic_1164.all;",
    ind .. "use ieee.numeric_std.all;",
    "",
    "-- Wrapper added by scripts/golden.lua so the fragment can be analysed.",
    "entity golden_wrapper is",
    ind .. "port (",
  }

  local ports = { { cfg.clock.name, ": in", "std_logic" } }
  if cfg.reset.style ~= "none" then
    ports[#ports + 1] = { cfg.reset.name, ": in", "std_logic" }
  end
  local aligned = style.align(ports)
  for index, line in ipairs(aligned) do
    out[#out + 1] = ind:rep(2) .. line .. (index < #aligned and ";" or "")
  end

  vim.list_extend(out, {
    ind .. ");",
    "end entity golden_wrapper;",
    "",
    "architecture golden of golden_wrapper is",
    "",
  })

  local function indented(depth)
    local result = {}
    for _, line in ipairs(body) do
      result[#result + 1] = line == "" and "" or (ind:rep(depth) .. line)
    end
    return result
  end

  -- A fragment may read signals it does not declare -- an edge detector reads
  -- the signal it watches. The template says what the wrapper must declare
  -- for the fixture to analyse, without putting those declarations into what
  -- a user would actually insert.
  local extra = {}
  if tpl.fixture_declarations then
    for _, line in ipairs(tpl.fixture_declarations(cfg, params)) do
      extra[#extra + 1] = ind .. line
    end
  end

  if scope == "mixed" then
    -- Declarations above `begin`, statements below: the whole reason the
    -- render function returns two halves.
    local declarations = {}
    for _, line in ipairs(render.lines(sections.declarations or "")) do
      declarations[#declarations + 1] = line == "" and "" or (ind .. line)
    end
    vim.list_extend(out, extra)
    vim.list_extend(out, declarations)
    vim.list_extend(out, { "", "begin", "" })
    vim.list_extend(out, indented(1))
    out[#out + 1] = ""
  elseif scope == "declarative" then
    vim.list_extend(out, indented(1))
    vim.list_extend(out, { "", "begin", "" })
  elseif scope == "statement" then
    vim.list_extend(out, extra)
    vim.list_extend(out, { "begin", "" })
    vim.list_extend(out, indented(1))
    out[#out + 1] = ""
  else -- sequential
    vim.list_extend(out, {
      "begin",
      "",
      ind .. "p_golden : process is",
      ind .. "begin",
    })
    vim.list_extend(out, indented(2))
    vim.list_extend(out, { ind .. "end process p_golden;", "" })
  end

  out[#out + 1] = "end architecture golden;"
  return out
end

--- A header naming exactly what produced the file, so a diff explains itself
--- without anyone having to work out which case moved.
local function header(tpl, variant, case)
  return {
    "-- GENERATED by scripts/golden.lua -- do not edit by hand.",
    ("-- template: %s   variant: %s   case: %s"):format(
      tpl.name,
      variant.name,
      case.label
    ),
    "",
  }
end

local function write(path, lines)
  local fd = assert(io.open(path, "w"))
  fd:write(table.concat(lines, "\n"))
  fd:write("\n")
  fd:close()
end

local function main()
  local templates = registry.list()
  if #templates == 0 then
    io.stderr:write("golden: no templates found on the runtimepath\n")
    os.exit(1)
  end

  local problems = registry.problems()
  if #problems > 0 then
    io.stderr:write("golden: templates failed to load:\n  ")
    io.stderr:write(table.concat(problems, "\n  ") .. "\n")
    os.exit(1)
  end

  vim.fn.mkdir(OUT .. "/vhdl", "p")
  vim.fn.mkdir(OUT .. "/external", "p")

  local written, failed = 0, 0
  for _, tpl in ipairs(templates) do
    for _, variant in ipairs(VARIANTS) do
      local cfg = config.resolve(config.merge(config.defaults, variant.cfg))
      for _, case in ipairs(param_cases(tpl)) do
        local sections, errors = render.sections(tpl, case.params, cfg)
        if not sections then
          io.stderr:write(
            ("golden: %s/%s/%s: %s\n"):format(
              tpl.name,
              variant.name,
              case.label,
              table.concat(errors, "; ")
            )
          )
          failed = failed + 1
        else
          local name = ("%s__%s__%s.vhd"):format(
            tpl.name,
            variant.name,
            case.label
          )
          local lines = header(tpl, variant, case)
          vim.list_extend(lines, wrap(tpl, cfg, sections, case.params))
          -- A template that needs a library CI does not have still gets
          -- fixtures, because they diff. They just live somewhere the GHDL
          -- step does not look.
          local dir = tpl.external_libraries and "external" or tpl.lang
          write(("%s/%s/%s"):format(OUT, dir, name), lines)
          written = written + 1
        end
      end
    end
  end

  io.stdout:write(("golden: wrote %d files to %s\n"):format(written, OUT))
  io.stdout:flush()
  os.exit(failed == 0 and 0 or 1)
end

main()
