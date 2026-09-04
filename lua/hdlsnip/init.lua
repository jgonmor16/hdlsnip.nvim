--- hdlsnip.nvim public API.
local config = require("hdlsnip.config")
local registry = require("hdlsnip.registry")
local render = require("hdlsnip.render")
local insert = require("hdlsnip.insert")
local ui = require("hdlsnip.ui")

local M = {}

--- Apply user options. Optional: the plugin works on its defaults, and the
--- commands are defined whether or not this is ever called.
---@param opts table?
---@return table cfg
function M.setup(opts)
  return config.setup(opts)
end

--- Resolve a template by name, reporting rather than throwing.
---@param name string
---@return table?
local function lookup(name)
  local tpl = registry.get(name)
  if not tpl then
    vim.notify(
      ("hdlsnip: no template named %q"):format(name),
      vim.log.levels.ERROR
    )
  end
  return tpl
end

--- Render a template and put it in the buffer.
---@param tpl table
---@param params table
---@param bufnr integer
local function render_and_insert(tpl, params, bufnr)
  local text, errors = render.values(tpl, params, config.get(bufnr))
  if not text then
    vim.notify(
      ("hdlsnip: %s\n  %s"):format(tpl.name, table.concat(errors, "\n  ")),
      vim.log.levels.ERROR
    )
    return
  end
  insert.insert_lines(bufnr, render.lines(text))
end

--- Insert a template, prompting for anything not supplied.
---
--- With no name, a picker opens first. With `params`, nothing is prompted --
--- that path is for mappings and for tests.
---@param name string?
---@param params table?
function M.insert(name, params)
  local bufnr = vim.api.nvim_get_current_buf()

  local function go(tpl)
    if params then
      return render_and_insert(tpl, params, bufnr)
    end
    ui.prompt_params(tpl, config.get(bufnr), function(prompted)
      render_and_insert(tpl, prompted, bufnr)
    end)
  end

  if name then
    local tpl = lookup(name)
    if tpl then
      go(tpl)
    end
    return
  end
  ui.select_template(nil, go)
end

--- Expand a template as a snippet, so its parameters become tabstops.
---
--- Dynamic templates cannot be snippets -- a tabstop cannot drive a loop or
--- decide whether a reset port exists -- so those fall back to prompting and
--- inserting. The distinction is deliberate but should not be the user's
--- problem at the point of use.
---@param name string?
function M.expand(name)
  local bufnr = vim.api.nvim_get_current_buf()

  local function go(tpl)
    if tpl.dynamic then
      return M.insert(tpl.name)
    end
    local body, errors = render.placeholders(tpl, config.get(bufnr))
    if not body then
      vim.notify(
        ("hdlsnip: %s\n  %s"):format(tpl.name, table.concat(errors, "\n  ")),
        vim.log.levels.ERROR
      )
      return
    end
    vim.snippet.expand(body)
  end

  if name then
    local tpl = lookup(name)
    if tpl then
      go(tpl)
    end
    return
  end
  ui.select_template(nil, go)
end

--- Rescan the runtimepath for templates.
function M.reload()
  registry.reload()
  vim.notify(
    ("hdlsnip: %d templates"):format(#registry.list()),
    vim.log.levels.INFO
  )
end

return M
