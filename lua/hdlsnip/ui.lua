--- Choosing a template or an entity
---
--- Through `vim.ui.select` when the user has replaced it -- telescope,
--- fzf-lua, snacks -- and through hdlsnip's own window otherwise, since the
--- built-in numbered prompt is nobody's preference. `picker` overrides the
--- choice either way.
---
--- Parameters are asked for by `hdlsnip.form`, which shows every field at
--- once rather than a question at a time.
local registry = require("hdlsnip.registry")

local M = {}

--- `vim.ui.select` as it was before a plugin could replace it.
---
--- Captured by `capture()` at startup: comparing against it is how we tell
--- whether the user has a picker of their own.
local pristine = nil

--- Remember the current `vim.ui.select`. Called from plugin/ at startup.
function M.capture()
  pristine = pristine or vim.ui.select
end

--- Choose from a list, through the user's picker when they have one.
---@param items table[]
---@param opts table `{ prompt, format_item }`
---@param on_choice fun(item: table?)
function M.choose(items, opts, on_choice)
  local cfg = require("hdlsnip.config").get_global()
  local replaced = pristine ~= nil and vim.ui.select ~= pristine

  if cfg.picker == "hdlsnip" or (cfg.picker == "auto" and not replaced) then
    opts.cfg = cfg
    return require("hdlsnip.form").select(items, opts, on_choice)
  end
  return vim.ui.select(items, opts, on_choice)
end

--- One line per template in the picker: kind, name, description.
---@param tpl table
---@return string
function M.format_template(tpl)
  return ("%-9s %-16s %s"):format(tpl.kind, tpl.name, tpl.desc)
end

--- Choose a template.
---@param filter table? passed to `registry.list`
---@param on_choice fun(tpl: table)
function M.select_template(filter, on_choice)
  local list = registry.list(filter)
  if #list == 0 then
    vim.notify("hdlsnip: no templates available", vim.log.levels.WARN)
    return
  end

  M.choose(list, {
    prompt = "hdlsnip: template",
    format_item = M.format_template,
    kind = "hdlsnip.template",
  }, function(choice)
    -- nil means the user cancelled, which is not an error.
    if choice then
      on_choice(choice)
    end
  end)
end

return M
