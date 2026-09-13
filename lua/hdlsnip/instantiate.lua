--- Instantiating an entity from elsewhere in the project.
---
--- The interface of a design already exists in a file; retyping it into an
--- instantiation is transcription, and transcription of twenty ports is where
--- a transposed pair hides until simulation.
local config = require("hdlsnip.config")
local entity = require("hdlsnip.vhdl.entity")
local generate = require("hdlsnip.vhdl.generate")
local insert = require("hdlsnip.insert")

local M = {}

--- VHDL files in the project, nearest first.
---
--- Searches from the buffer's directory upward to the root marker, so a large
--- monorepo does not scan everything. Falls back to the working directory.
---@param bufnr integer
---@return string[]
function M.sources(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  -- By path rather than by buffer number: with a buffer whose file does not
  -- exist, vim.fs.root falls back to the working directory and the search
  -- runs somewhere entirely unrelated.
  local root = name ~= ""
      and vim.fs.root(name, { ".git", "vhdl_ls.toml", ".hdlsnip.lua" })
    or nil
  -- The buffer's own directory before the working directory: with no root
  -- marker, the files beside you are a better guess than wherever Neovim
  -- happens to have been started.
  root = root or (name ~= "" and vim.fs.dirname(name)) or vim.uv.cwd()

  -- globpath rather than vim.fs.find: the pattern is simple, `**` already
  -- means every depth, and the predicate form of find returns nothing here.
  local found = vim.fn.globpath(root, "**/*.vhd", false, true)
  vim.list_extend(found, vim.fn.globpath(root, "**/*.vhdl", false, true))

  -- Nearest first: a file beside the buffer is likelier than one in a
  -- sibling tree.
  local here = name ~= "" and vim.fs.dirname(name) or root
  table.sort(found, function(a, b)
    local a_here = vim.fs.dirname(a) == here
    local b_here = vim.fs.dirname(b) == here
    if a_here ~= b_here then
      return a_here
    end
    return a < b
  end)

  return found
end

--- Every entity found in the project, as pick-able choices.
---@param bufnr integer
---@return table[] `{ name, path, entity }`
function M.entities(bufnr)
  local out = {}
  for _, path in ipairs(M.sources(bufnr)) do
    local parsed = entity.from_file(path)
    -- An entity with no ports is legal but nothing to instantiate.
    if parsed and #parsed.ports > 0 then
      out[#out + 1] = { name = parsed.name, path = path, entity = parsed }
    end
  end
  return out
end

--- Render an entity as an instantiation, optionally with its signals.
---@param parsed table
---@param cfg table
---@param opts table? `{ signals = boolean, label, library, component }`
---@return table sections `{ declarations = string?, statements = string }`
function M.sections(parsed, cfg, opts)
  opts = opts or {}
  local values = opts.signals and generate.signal_values(parsed, cfg) or {}

  return {
    declarations = opts.signals and generate.signals(parsed, cfg) or nil,
    statements = generate.instantiate(parsed, cfg, {
      label = opts.label,
      library = opts.library,
      component = opts.component,
      values = values,
    }),
  }
end

--- Insert an instantiation of `choice` into the buffer.
---@param choice table from `M.entities`
---@param bufnr integer
---@param opts table?
local function place(choice, bufnr, opts)
  local cfg = config.get(bufnr)
  insert.insert_sections(bufnr, M.sections(choice.entity, cfg, opts), cfg)
end

--- Instantiate an entity, choosing one when no name is given.
---@param name string?
---@param opts table? `{ signals = boolean, label, library, component }`
function M.instantiate(name, opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local choices = M.entities(bufnr)

  if #choices == 0 then
    vim.notify(
      "hdlsnip: no entity with ports found in the project",
      vim.log.levels.WARN
    )
    return
  end

  if name then
    for _, choice in ipairs(choices) do
      if choice.name == name then
        return place(choice, bufnr, opts)
      end
    end
    vim.notify(
      ("hdlsnip: no entity named %q in the project"):format(name),
      vim.log.levels.ERROR
    )
    return
  end

  vim.ui.select(choices, {
    prompt = "hdlsnip: entity",
    format_item = function(choice)
      return ("%-24s %d ports  %s"):format(
        choice.name,
        #choice.entity.ports,
        vim.fn.fnamemodify(choice.path, ":.")
      )
    end,
    kind = "hdlsnip.entity",
  }, function(choice)
    if choice then
      place(choice, bufnr, opts)
    end
  end)
end

--- Names of every entity found, for command completion.
---@return string[]
function M.names()
  local out = {}
  for index, choice in ipairs(M.entities(vim.api.nvim_get_current_buf())) do
    out[index] = choice.name
  end
  return out
end

return M
