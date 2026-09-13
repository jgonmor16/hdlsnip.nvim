--- Reading an entity declaration.
---
--- Enough of VHDL to pull the name, generics and ports out of an entity, so
--- an instantiation can be generated from it rather than retyped. Not a
--- parser for the language: it understands entity declarations and nothing
--- else, and says so when it is unsure.
---
--- A line parser rather than treesitter, for the same reason as
--- `hdlsnip.placement`: Neovim ships no VHDL parser, and the plugin otherwise
--- needs nothing.
local M = {}

--- Strip comments and collapse whitespace, leaving a single string.
---
--- Declarations wrap across lines freely in VHDL, so the clause is easier to
--- read as one string than line by line.
---@param lines string[]
---@return string
local function flatten(lines)
  local out = {}
  for _, line in ipairs(lines) do
    -- Comments only: a `--` inside a string literal is vanishingly rare in an
    -- entity declaration, and getting it wrong costs a bad parse, not a crash.
    local code = line:gsub("%-%-.*$", "")
    out[#out + 1] = code
  end
  return (table.concat(out, " "):gsub("%s+", " "))
end

--- The text between the parentheses that follow `keyword`, or nil.
---
--- Counts depth, so a default value containing parentheses does not end the
--- clause early.
---@param text string
---@param keyword string
---@return string?
local function clause(text, keyword)
  local start = text:lower():find(keyword .. "%s*%(")
  if not start then
    return nil
  end

  local open = text:find("%(", start)
  local depth, index = 0, open
  while index <= #text do
    local char = text:sub(index, index)
    if char == "(" then
      depth = depth + 1
    elseif char == ")" then
      depth = depth - 1
      if depth == 0 then
        return text:sub(open + 1, index - 1)
      end
    end
    index = index + 1
  end
  return nil
end

--- Split on semicolons that are not inside parentheses.
---@param text string
---@return string[]
local function split_declarations(text)
  local out, depth, current = {}, 0, {}
  for index = 1, #text do
    local char = text:sub(index, index)
    if char == "(" then
      depth = depth + 1
    elseif char == ")" then
      depth = depth - 1
    end
    if char == ";" and depth == 0 then
      out[#out + 1] = table.concat(current)
      current = {}
    else
      current[#current + 1] = char
    end
  end
  local last = table.concat(current):match("^%s*(.-)%s*$")
  if last ~= "" then
    out[#out + 1] = last
  end
  return out
end

local MODES =
  { ["in"] = true, out = true, inout = true, buffer = true, linkage = true }

--- Parse one interface declaration: `a, b : in std_logic := '0'`.
---@param text string
---@param default_mode string?
---@return table[] entries
local function interface(text, default_mode)
  local names, rest = text:match("^%s*([%w_%s,]-)%s*:%s*(.+)$")
  if not names or names == "" then
    return {}
  end

  -- An explicit `signal`, `constant` or `variable` before the mode is legal
  -- and carries no information we need.
  rest = rest:gsub("^%s*[Ss][Ii][Gg][Nn][Aa][Ll]%s+", "")
  rest = rest:gsub("^%s*[Cc][Oo][Nn][Ss][Tt][Aa][Nn][Tt]%s+", "")

  local mode = rest:match("^(%a+)%s")
  if mode and MODES[mode:lower()] then
    rest = rest:sub(#mode + 1)
  else
    mode = default_mode
  end

  local subtype, default = rest:match("^%s*(.-)%s*:=%s*(.+)$")
  if not subtype then
    subtype = rest:match("^%s*(.-)%s*$")
  end

  local entries = {}
  for name in names:gmatch("[%w_]+") do
    entries[#entries + 1] = {
      name = name,
      mode = mode and mode:lower() or nil,
      subtype = subtype,
      default = default,
    }
  end
  return entries
end

--- Parse the first entity declaration in `lines`.
---@param lines string[]
---@return table? entity `{ name, generics, ports }`
---@return string? err
function M.parse(lines)
  local text = flatten(lines)

  local name = text:match("[Ee][Nn][Tt][Ii][Tt][Yy]%s+([%a][%w_]*)%s+[Ii][Ss]")
  if not name then
    return nil, "no entity declaration found"
  end

  -- Everything from the entity keyword to its end, so a later entity in the
  -- same file cannot contribute ports to this one.
  local from = text:find("[Ee][Nn][Tt][Ii][Tt][Yy]%s+" .. name)
  local to = text:find("[Ee][Nn][Dd]%s[^;]*;", from) or #text
  local body = text:sub(from, to)

  local entity = { name = name, generics = {}, ports = {} }

  local generic_clause = clause(body, "generic")
  if generic_clause then
    for _, declaration in ipairs(split_declarations(generic_clause)) do
      vim.list_extend(entity.generics, interface(declaration, nil))
    end
  end

  local port_clause = clause(body, "port")
  if port_clause then
    for _, declaration in ipairs(split_declarations(port_clause)) do
      -- A port with no mode is an input, per the LRM.
      vim.list_extend(entity.ports, interface(declaration, "in"))
    end
  end

  return entity, nil
end

--- Parse the entity in a buffer.
---@param bufnr integer
---@return table?
---@return string?
function M.from_buffer(bufnr)
  return M.parse(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
end

--- Parse the entity in a file.
---@param path string
---@return table?
---@return string?
function M.from_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, ("cannot read %s"):format(path)
  end
  return M.parse(lines)
end

return M
