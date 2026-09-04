--- Interactive selection and prompting.
---
--- Everything goes through `vim.ui.select` and `vim.ui.input`, so whatever
--- the user has installed -- telescope, fzf-lua, snacks, or the built-in
--- prompts -- is what they get. No picker is bundled and none is required.
local registry = require("hdlsnip.registry")
local template = require("hdlsnip.template")

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

--- Prompt for every parameter in order, then hand back the values.
---
--- Invalid input re-prompts for the same parameter instead of failing at the
--- end. Discovering that a width had to be at least 1 only after answering
--- four more questions would be its own small punishment.
---@param tpl table
---@param cfg table
---@param on_done fun(params: table)
function M.prompt_params(tpl, cfg, on_done)
  local values = {}

  local function step(index)
    local param = tpl.params and tpl.params[index]
    if not param then
      return on_done(values)
    end

    local label = ("%s (%s)"):format(param.desc, param.name)

    if param.type == "boolean" or param.type == "choice" then
      local choices
      if param.type == "boolean" then
        -- Offer the default first, so hitting enter keeps it.
        choices = param.default and { "true", "false" } or { "false", "true" }
      else
        choices = { param.default }
        for _, choice in ipairs(param.choices) do
          if choice ~= param.default then
            choices[#choices + 1] = choice
          end
        end
      end

      vim.ui.select(choices, { prompt = label }, function(choice)
        if choice == nil then
          return
        end
        values[param.name] = choice
        step(index + 1)
      end)
      return
    end

    vim.ui.input({
      prompt = label .. ": ",
      default = tostring(param.default),
    }, function(input)
      if input == nil then
        return
      end
      local value, err = template.coerce(param, input, cfg)
      if err then
        vim.notify(
          ("hdlsnip: %s: %s"):format(param.name, err),
          vim.log.levels.WARN
        )
        return step(index) -- ask again for the same parameter
      end
      values[param.name] = value
      step(index + 1)
    end)
  end

  step(1)
end

return M
