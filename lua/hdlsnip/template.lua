--- Template and parameter specifications.
---
--- A template is a plain table. This module is the contract: it validates the
--- table at registration time so a malformed template fails loudly during
--- development rather than emitting broken VHDL into a buffer, and it coerces
--- user input (always strings, coming from `vim.ui.input`) into typed values.
local style = require("hdlsnip.style")

local M = {}

--- Parameter types a template may declare.
M.types = {
  string = true,
  identifier = true,
  integer = true,
  number = true,
  boolean = true,
  choice = true,
}

--- Categories a template may belong to. Used for grouping in the picker.
M.kinds = {
  skeleton = true,
  rtl = true,
  cdc = true,
  mem = true,
  bus = true,
  tb = true,
}

local BOOL = {
  ["true"] = true,
  ["yes"] = true,
  ["y"] = true,
  ["1"] = true,
  ["false"] = false,
  ["no"] = false,
  ["n"] = false,
  ["0"] = false,
}

-- ---------------------------------------------------------------------------
-- Coercion
-- ---------------------------------------------------------------------------

--- Turn a raw value into the parameter's declared type and check its bounds.
--- Input from the UI arrives as a string; input from the Lua API may already
--- be typed, so both are accepted.
---@param param table
---@param raw any
---@param cfg table
---@return any? value nil on failure
---@return string? err
function M.coerce(param, raw, cfg)
  if raw == nil then
    return nil, "missing"
  end

  if param.type == "boolean" then
    local v = type(raw) == "boolean" and raw or BOOL[tostring(raw):lower()]
    if v == nil then
      return nil, "expected a boolean"
    end
    return v
  end

  if param.type == "integer" or param.type == "number" then
    local n = tonumber(raw)
    if n == nil then
      return nil, ("expected a number, got %q"):format(tostring(raw))
    end
    if param.type == "integer" and n % 1 ~= 0 then
      return nil, ("expected an integer, got %s"):format(tostring(n))
    end
    if param.min and n < param.min then
      return nil, ("must be >= %s"):format(param.min)
    end
    if param.max and n > param.max then
      return nil, ("must be <= %s"):format(param.max)
    end
    return n
  end

  local s = tostring(raw)

  if param.type == "choice" then
    for _, allowed in ipairs(param.choices) do
      if s == allowed then
        return s
      end
    end
    return nil, ("expected one of %s"):format(table.concat(param.choices, ", "))
  end

  if param.type == "identifier" then
    if not style.is_legal_identifier(cfg, s) then
      return nil,
        ("%q is not a legal VHDL-%s identifier"):format(s, cfg.vhdl_std)
    end
    return s
  end

  if param.check then
    local ok, why = param.check(s, cfg)
    if not ok then
      return nil, why or "invalid"
    end
  end
  return s
end

--- Resolve every parameter of a template: defaults for anything not given,
--- coercion and bounds checking for everything else.
---@param tpl table
---@param given table<string, any>?
---@param cfg table
---@return table? values nil when any parameter is invalid
---@return string[] errors
function M.resolve_params(tpl, given, cfg)
  given = given or {}
  local values, errors = {}, {}

  for _, param in ipairs(tpl.params or {}) do
    local raw = given[param.name]
    if raw == nil then
      raw = param.default
    end
    local value, err = M.coerce(param, raw, cfg)
    if err then
      errors[#errors + 1] = ("%s.%s: %s"):format(tpl.name, param.name, err)
    else
      values[param.name] = value
    end
  end

  for key in pairs(given) do
    local declared = false
    for _, param in ipairs(tpl.params or {}) do
      declared = declared or param.name == key
    end
    if not declared then
      errors[#errors + 1] = ("%s: unknown parameter %q"):format(tpl.name, key)
    end
  end

  if #errors > 0 then
    return nil, errors
  end
  return values, errors
end

-- ---------------------------------------------------------------------------
-- Template validation
-- ---------------------------------------------------------------------------

--- Every `{{marker}}` in a body, in order of first appearance.
---@param body string
---@return string[]
function M.markers(body)
  local seen, order = {}, {}
  for key in body:gmatch("{{%s*([%w_]+)%s*}}") do
    if not seen[key] then
      seen[key] = true
      order[#order + 1] = key
    end
  end
  return order
end

local function validate_param(param, index, errors)
  local at = ("params[%d]"):format(index)
  if type(param.name) ~= "string" or not param.name:match("^%l[%l%d_]*$") then
    errors[#errors + 1] = ("%s: name must be lower_snake_case"):format(at)
    return
  end
  at = ("param %q"):format(param.name)

  if not M.types[param.type] then
    errors[#errors + 1] = ("%s: unknown type %q"):format(
      at,
      tostring(param.type)
    )
    return
  end
  if type(param.desc) ~= "string" or param.desc == "" then
    errors[#errors + 1] = ("%s: needs a desc, it is shown in the prompt"):format(
      at
    )
  end
  if param.default == nil then
    errors[#errors + 1] = ("%s: needs a default"):format(at)
  end
  if param.type == "choice" then
    if type(param.choices) ~= "table" or #param.choices == 0 then
      errors[#errors + 1] = ("%s: choice needs a non-empty choices list"):format(
        at
      )
      return
    end
    local ok = false
    for _, choice in ipairs(param.choices) do
      ok = ok or choice == param.default
    end
    if not ok then
      errors[#errors + 1] = ("%s: default is not one of the choices"):format(at)
    end
  end
  if param.min and param.max and param.min > param.max then
    errors[#errors + 1] = ("%s: min is greater than max"):format(at)
  end
end

--- Validate a template specification.
---@param tpl table
---@return boolean ok
---@return string[] errors
function M.validate(tpl)
  local errors = {}

  if type(tpl.name) ~= "string" or not tpl.name:match("^%l[%l%d_]*$") then
    errors[#errors + 1] = "name must be lower_snake_case"
    return false, errors -- later messages would have nothing to name
  end
  if type(tpl.desc) ~= "string" or tpl.desc == "" then
    errors[#errors + 1] = ("%s: needs a desc"):format(tpl.name)
  end
  if not M.kinds[tpl.kind] then
    errors[#errors + 1] = ("%s: unknown kind %q"):format(
      tpl.name,
      tostring(tpl.kind)
    )
  end

  local has_body = type(tpl.body) == "string"
  local has_render = type(tpl.render) == "function"
  if has_body == has_render then
    errors[#errors + 1] = ("%s: needs exactly one of body or render"):format(
      tpl.name
    )
  end
  if has_render and not tpl.dynamic then
    errors[#errors + 1] = ("%s: a render function requires dynamic = true"):format(
      tpl.name
    )
  end
  if has_body and tpl.dynamic then
    errors[#errors + 1] = ("%s: a string body cannot be dynamic"):format(
      tpl.name
    )
  end

  local names = {}
  for index, param in ipairs(tpl.params or {}) do
    validate_param(param, index, errors)
    if param.name then
      if names[param.name] then
        errors[#errors + 1] = ("%s: duplicate param %q"):format(
          tpl.name,
          param.name
        )
      end
      names[param.name] = true
    end
  end

  -- A static body is checkable both ways: no marker without a parameter, and
  -- no parameter without a marker. The second half catches the rename that
  -- updated the body and left the params list behind.
  if has_body then
    local used = {}
    for _, marker in ipairs(M.markers(tpl.body)) do
      used[marker] = true
      if marker ~= "cursor" and not names[marker] then
        errors[#errors + 1] = ("%s: body uses {{%s}}, which is not a param"):format(
          tpl.name,
          marker
        )
      end
    end
    for name in pairs(names) do
      if not used[name] then
        errors[#errors + 1] = ("%s: param %q is never used in the body"):format(
          tpl.name,
          name
        )
      end
    end
  end

  table.sort(errors)
  return #errors == 0, errors
end

return M
