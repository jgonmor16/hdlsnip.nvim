--- Choosing a template.
---
--- Goes through `vim.ui.select`, so whatever picker the user has installed --
--- telescope, fzf-lua, snacks, or the built-in prompt -- is what they get.
--- None is bundled and none is required.
---
--- Parameters are asked for by `hdlsnip.form`, which shows every field at
--- once rather than a question at a time.
local registry = require("hdlsnip.registry")

local M = {}

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

  vim.ui.select(list, {
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
