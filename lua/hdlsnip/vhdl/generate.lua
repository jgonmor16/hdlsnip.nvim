--- Writing VHDL from a parsed entity.
---
--- The instantiation of a 19-port AXI4-Lite slave is twenty lines of typing
--- with a transposition error waiting in it. Reading the entity and writing
--- the instantiation removes both.
---
--- Named association throughout, never positional: positional association
--- compiles happily with two ports of the same type swapped, and the
--- resulting bug is found in simulation rather than at analysis.
local style = require("hdlsnip.style")

local M = {}

--- What each generic is given in the instantiation.
---
--- Its default when it has one, its own name otherwise -- which will not
--- analyse, and is meant not to: a generic with no default has to be supplied
--- and leaving the name there says so plainly.
---@param parsed table
---@param values table<string, string>?
---@return table<string, string>
function M.generic_values(parsed, values)
  local out = {}
  for _, generic in ipairs(parsed.generics) do
    out[generic.name] = (values or {})[generic.name]
      or generic.default
      or generic.name
  end
  return out
end

--- Substitute generic values into a subtype.
---
--- A port declared `std_logic_vector(G_WIDTH - 1 downto 0)` cannot be copied
--- into a signal declaration as it stands: the instantiating scope has no
--- G_WIDTH. The value the instance gives it goes in instead.
---@param subtype string
---@param parsed table
---@param values table<string, string>
---@return string
local function resolve(subtype, parsed, values)
  local out = subtype
  for _, generic in ipairs(parsed.generics) do
    local value = values[generic.name]
    if value and value ~= generic.name then
      -- Word boundaries, so G_WIDTH does not match inside G_WIDTH_BYTES.
      out = out:gsub("%f[%w_]" .. generic.name .. "%f[^%w_]", value)
    end
  end
  return out
end

--- The widest name in a list, for aligning the association columns.
---@param entries table[]
---@return integer
local function widest(entries)
  local width = 0
  for _, entry in ipairs(entries) do
    width = math.max(width, #entry.name)
  end
  return width
end

--- A generic or port map, as indented lines.
---@param keyword string `generic` or `port`
---@param entries table[]
---@param values table<string, string> what each name maps to
---@param cfg table
---@param depth integer
---@return string[]
local function association(keyword, entries, values, cfg, depth)
  local kw = style.kw(cfg)
  local ind = cfg.indent
  local width = widest(entries)
  local lines = { ("%s%s %s ("):format(ind:rep(depth), kw(keyword), kw("map")) }

  for index, entry in ipairs(entries) do
    lines[#lines + 1] = ("%s%-" .. width .. "s => %s%s"):format(
      ind:rep(depth + 1),
      entry.name,
      values[entry.name] or entry.name,
      index < #entries and "," or ""
    )
  end

  lines[#lines + 1] = ("%s)"):format(ind:rep(depth))
  return lines
end

--- Instantiate an entity.
---
--- Direct instantiation by default -- `entity work.name` -- which needs no
--- component declaration. Set `component = true` for the older form, which a
--- VHDL-93 design or a vendor flow may still require.
---@param parsed table from `hdlsnip.vhdl.entity`
---@param cfg table
---@param opts table? `{ label, library, component, values }`
---@return string
function M.instantiate(parsed, cfg, opts)
  opts = opts or {}
  local kw = style.kw(cfg)
  local ind = cfg.indent
  local label = opts.label or ("%s_inst"):format(parsed.name)
  local values = opts.values or {}
  local lines = {}

  if opts.component then
    lines[#lines + 1] = ("%s : %s %s"):format(label, parsed.name, kw("is"))
    -- `label : name` on its own is the component form; no library prefix.
    lines[1] = ("%s : %s"):format(label, parsed.name)
  else
    lines[#lines + 1] = ("%s : %s %s.%s"):format(
      label,
      kw("entity"),
      opts.library or "work",
      parsed.name
    )
  end

  if #parsed.generics > 0 then
    vim.list_extend(
      lines,
      association(
        "generic",
        parsed.generics,
        M.generic_values(parsed, values),
        cfg,
        1
      )
    )
  end

  if #parsed.ports > 0 then
    vim.list_extend(lines, association("port", parsed.ports, values, cfg, 1))
  end

  lines[#lines] = lines[#lines] .. ";"
  return table.concat(lines, "\n")
end

--- A component declaration, for designs that still need one.
---@param parsed table
---@param cfg table
---@return string
function M.component(parsed, cfg)
  local kw = style.kw(cfg)
  local ind = cfg.indent
  local lines = {
    ("%s %s %s"):format(kw("component"), parsed.name, kw("is")),
  }

  local function interface(keyword, entries)
    local rows = {}
    for _, entry in ipairs(entries) do
      local subtype = entry.subtype
        .. (entry.default and (" := " .. entry.default) or "")
      if entry.mode then
        rows[#rows + 1] =
          { entry.name, (": %s"):format(kw(entry.mode)), subtype }
      else
        -- Generics have no mode, and an empty cell would still be padded,
        -- leaving a gap where the mode would have been.
        rows[#rows + 1] = { entry.name, ": " .. subtype }
      end
    end

    lines[#lines + 1] = ("%s%s ("):format(ind, kw(keyword))
    local aligned = style.align(rows)
    for index, line in ipairs(aligned) do
      -- The last one takes no semicolon; the closing paren ends the clause.
      lines[#lines + 1] = ind:rep(2) .. line .. (index < #aligned and ";" or "")
    end
    lines[#lines + 1] = ("%s);"):format(ind)
  end

  if #parsed.generics > 0 then
    interface("generic", parsed.generics)
  end
  if #parsed.ports > 0 then
    interface("port", parsed.ports)
  end

  lines[#lines + 1] = ("%s %s %s;"):format(
    kw("end"),
    kw("component"),
    parsed.name
  )
  return table.concat(lines, "\n")
end

--- Signal declarations for every port, to wire an instance up.
---
--- Named after the port, with the configured direction suffixes stripped: a
--- signal driving `wr_en_i` is not itself an input to anything. Generic
--- values are substituted into the subtypes, since the instantiating scope
--- has no G_WIDTH of its own.
---@param parsed table
---@param cfg table
---@param values table<string, string>? generic values, defaults otherwise
---@return string
function M.signals(parsed, cfg, values)
  local kw = style.kw(cfg)
  local generics = M.generic_values(parsed, values)
  local rows = {}

  for _, port in ipairs(parsed.ports) do
    local name = port.name
    for _, suffix in ipairs({ cfg.naming.in_suffix, cfg.naming.out_suffix }) do
      if suffix ~= "" and name:sub(-#suffix) == suffix then
        name = name:sub(1, -#suffix - 1)
        break
      end
    end
    rows[#rows + 1] =
      { name, (": %s;"):format(resolve(port.subtype, parsed, generics)) }
  end

  local lines = {}
  for _, line in ipairs(style.align(rows)) do
    lines[#lines + 1] = kw("signal") .. " " .. line
  end
  return table.concat(lines, "\n")
end

--- The map from port name to the signal `signals()` declares for it.
---@param parsed table
---@param cfg table
---@return table<string, string>
function M.signal_values(parsed, cfg)
  local values = {}
  for _, port in ipairs(parsed.ports) do
    local name = port.name
    for _, suffix in ipairs({ cfg.naming.in_suffix, cfg.naming.out_suffix }) do
      if suffix ~= "" and name:sub(-#suffix) == suffix then
        name = name:sub(1, -#suffix - 1)
        break
      end
    end
    values[port.name] = name
  end
  return values
end

return M
