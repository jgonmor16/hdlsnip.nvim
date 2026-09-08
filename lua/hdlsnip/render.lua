--- Rendering.
---
--- One template source serves three consumers, which is the whole point of
--- the engine:
---
---   values       -> plain VHDL, for :HdlSnip, golden fixtures and GHDL in CI
---   placeholders -> an LSP snippet body, for vim.snippet, LuaSnip and the
---                   VS Code JSON export
---
--- Dynamic templates -- the ones whose output depends on a parameter, such as
--- an N-stage synchroniser or an N-register file -- can only be rendered in
--- values mode. A tabstop cannot drive a loop, so those are prompted for
--- first and inserted fully formed.
local template = require("hdlsnip.template")
local style = require("hdlsnip.style")

local M = {}

-- ---------------------------------------------------------------------------
-- LSP snippet escaping
-- ---------------------------------------------------------------------------

--- Escape literal text destined for a snippet body. Backslash first, or the
--- backslashes introduced for `$` would themselves be escaped.
---@param s string
---@return string
function M.escape_literal(s)
  return (s:gsub("\\", "\\\\"):gsub("%$", "\\$"))
end

--- Escape a placeholder default, which additionally sits inside braces.
---@param s string
---@return string
function M.escape_placeholder(s)
  return (s:gsub("\\", "\\\\"):gsub("([%$}])", "\\%1"))
end

--- Escape one alternative of a choice placeholder. Commas and pipes would
--- otherwise end the alternative.
---@param s string
---@return string
function M.escape_choice(s)
  return (s:gsub("\\", "\\\\"):gsub("([%$|,}])", "\\%1"))
end

-- ---------------------------------------------------------------------------
-- Substitution
-- ---------------------------------------------------------------------------

--- Replace every `{{marker}}` using `fn`. An unhandled marker is an error:
--- silently emitting an empty string would produce VHDL that looks plausible
--- and analyses wrong.
---@param body string
---@param fn fun(marker: string): string?
---@param name string template name, for the error message
---@return string
function M.substitute(body, fn, name)
  return (
    body:gsub("{{%s*([%w_]+)%s*}}", function(marker)
      local replacement = fn(marker)
      if replacement == nil then
        error(("hdlsnip: %s: no value for {{%s}}"):format(name, marker), 0)
      end
      return replacement
    end)
  )
end

--- Format a resolved value for insertion into VHDL.
---@param value any
---@return string
local function literal(value)
  if type(value) == "number" and value % 1 == 0 then
    return ("%d"):format(value) -- 8, never 8.0
  end
  if type(value) == "boolean" then
    return tostring(value)
  end
  return tostring(value)
end

-- ---------------------------------------------------------------------------
-- Modes
-- ---------------------------------------------------------------------------

--- Render a template into its declarative and statement halves.
---
--- Most templates produce one block of text and it goes wherever the cursor
--- is. A `mixed` template produces two, because an FSM's state type belongs
--- above `begin` and its processes below: the halves are kept apart so a
--- caller can place each correctly.
---@param tpl table
---@param given table<string, any>?
---@param cfg table
---@return table? sections `{ declarations = string?, statements = string }`
---@return string[] errors
function M.sections(tpl, given, cfg)
  local params, errors = template.resolve_params(tpl, given, cfg)
  if not params then
    return nil, errors
  end

  if not tpl.dynamic then
    local text = M.substitute(style.apply_case(tpl.body, cfg), function(marker)
      if marker == "cursor" then
        return ""
      end
      local value = params[marker]
      return value ~= nil and literal(value) or nil
    end, tpl.name)
    return { statements = text }, {}
  end

  local ok, result = pcall(tpl.render, params, cfg)
  if not ok then
    return nil, { ("%s: %s"):format(tpl.name, result) }
  end

  if type(result) == "string" then
    return { statements = result }, {}
  end
  if type(result) ~= "table" then
    return nil,
      {
        ("%s: render returned %s, expected a string or a table"):format(
          tpl.name,
          type(result)
        ),
      }
  end
  return result, {}
end

--- Render concrete VHDL.
---@param tpl table
---@param given table<string, any>?
---@param cfg table
---@return string? text
---@return string[] errors
function M.values(tpl, given, cfg)
  local sections, errors = M.sections(tpl, given, cfg)
  if not sections then
    return nil, errors
  end

  -- Flattened in the order they would be written, which is what an insertion
  -- at the cursor wants. Callers that can place the halves separately use
  -- `sections` instead.
  if sections.declarations and sections.declarations ~= "" then
    return sections.declarations .. "\n\n" .. (sections.statements or ""), {}
  end
  return sections.statements or "", {}
end

--- Render an LSP snippet body.
---
--- Tabstops are numbered by first appearance in the body rather than by
--- declaration order, so tabbing through the snippet moves down the page.
--- Repeated parameters become mirrors of their first occurrence.
---@param tpl table
---@param cfg table
---@return string? body
---@return string[] errors
function M.placeholders(tpl, cfg)
  if tpl.dynamic then
    return nil,
      {
        ("%s: dynamic templates render in values mode only"):format(tpl.name),
      }
  end

  local by_name = {}
  for _, param in ipairs(tpl.params or {}) do
    by_name[param.name] = param
  end

  local assigned, next_index = {}, 0
  local cased = style.apply_case(tpl.body, cfg)
  local body = M.substitute(M.escape_literal(cased), function(marker)
    if marker == "cursor" then
      return "$0"
    end
    if assigned[marker] then
      return "$" .. assigned[marker]
    end
    local param = by_name[marker]
    if not param then
      return nil
    end

    next_index = next_index + 1
    assigned[marker] = next_index

    if param.type == "choice" then
      local alts = {}
      for i, choice in ipairs(param.choices) do
        alts[i] = M.escape_choice(choice)
      end
      return ("${%d|%s|}"):format(next_index, table.concat(alts, ","))
    end
    if param.type == "boolean" then
      local first = tostring(param.default)
      local second = tostring(not param.default)
      return ("${%d|%s,%s|}"):format(next_index, first, second)
    end
    return ("${%d:%s}"):format(
      next_index,
      M.escape_placeholder(literal(param.default))
    )
  end, tpl.name)

  -- Without an explicit {{cursor}}, leave the caret after the snippet rather
  -- than back at tabstop 1, which is where an implicit $0 would put it.
  if not tpl.body:find("{{%s*cursor%s*}}") then
    body = body .. "$0"
  end

  return body, {}
end

--- Render in the requested mode.
---@param tpl table
---@param mode "values"|"placeholders"
---@param given table<string, any>?
---@param cfg table
---@return string? text
---@return string[] errors
function M.render(tpl, mode, given, cfg)
  if mode == "placeholders" then
    return M.placeholders(tpl, cfg)
  end
  return M.values(tpl, given, cfg)
end

--- Split rendered text into buffer lines, stripping trailing whitespace and
--- any leading or trailing blank line the template's own formatting left
--- behind.
---@param text string
---@return string[]
function M.lines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    out[#out + 1] = (line:gsub("%s+$", ""))
  end
  while out[1] == "" do
    table.remove(out, 1)
  end
  while out[#out] == "" do
    table.remove(out)
  end
  return out
end

return M
