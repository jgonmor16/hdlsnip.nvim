--- Instantiating an entity from elsewhere in the project.
---
--- The interface of a design already exists in a file; retyping it into an
--- instantiation is transcription, and transcription of twenty ports is where
--- a transposed pair hides until simulation.
local config = require("hdlsnip.config")
local entity = require("hdlsnip.vhdl.entity")
local generate = require("hdlsnip.vhdl.generate")
local insert = require("hdlsnip.insert")
local ui = require("hdlsnip.ui")
local testbench = require("hdlsnip.vhdl.testbench")

local M = {}

--- Directories whose contents are not designs anybody wants to instantiate.
---
--- Generated output and vendor build trees hold hundreds of VHDL files, and
--- offering them buries the handful that matter.
local IGNORED = {
  "%.git/",
  "/tests/golden/",
  "/vunit_out/",
  "/work%-obj",
  "/%.Xil/",
  "/xsim%.dir/",
  "/db/",
  "/incremental_db/",
  "/output_files/",
  "/simulation/",
}

---@param path string
---@return boolean
local function ignored(path)
  for _, pattern in ipairs(IGNORED) do
    if path:find(pattern) then
      return true
    end
  end
  return false
end

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
  -- Both forms of each pattern: `**` does not match a file sitting directly
  -- in the root.
  local found = {}
  for _, pattern in ipairs({ "*.vhd", "*.vhdl", "**/*.vhd", "**/*.vhdl" }) do
    vim.list_extend(found, vim.fn.globpath(root, pattern, false, true))
  end

  -- `**` matches zero directories on some systems, so the plain and the
  -- recursive pattern return the same file and it would be offered twice.
  local seen, kept = {}, {}
  for _, path in ipairs(found) do
    if not ignored(path) and not seen[path] then
      seen[path] = true
      kept[#kept + 1] = path
    end
  end
  found = kept

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

  ui.choose(choices, {
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

--- Write a testbench for `choice` into a buffer.
---
--- A testbench is a whole file, so it does not go in at the cursor. An empty
--- buffer is used as it stands; anything else gets a new one named after the
--- entity, beside its source.
---@param choice table from `M.entities`
---@param opts table?
local function place_testbench(choice, opts)
  local cfg = config.get(vim.api.nvim_get_current_buf())
  local text = testbench.build(choice.entity, cfg, opts)
  local lines = vim.split(text, "\n", { plain = true })

  local current = vim.api.nvim_get_current_buf()
  local empty = vim.api.nvim_buf_get_name(current) == ""
    and vim.api.nvim_buf_line_count(current) == 1
    and vim.api.nvim_buf_get_lines(current, 0, 1, false)[1] == ""

  if not empty then
    local path = ("%s/tb_%s.vhd"):format(
      vim.fs.dirname(choice.path),
      choice.entity.name
    )
    vim.cmd.edit(vim.fn.fnameescape(path))
    current = vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_line_count(current) > 1 then
      vim.notify(
        ("hdlsnip: %s already exists"):format(vim.fn.fnamemodify(path, ":.")),
        vim.log.levels.WARN
      )
      return
    end
  end

  vim.api.nvim_buf_set_lines(current, 0, -1, false, lines)
  vim.bo[current].filetype = "vhdl"
end

--- Write a testbench around an entity, choosing one when no name is given.
---@param name string?
---@param opts table? `{ period_ns, library }`
function M.testbench(name, opts)
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
        return place_testbench(choice, opts)
      end
    end
    vim.notify(
      ("hdlsnip: no entity named %q in the project"):format(name),
      vim.log.levels.ERROR
    )
    return
  end

  ui.choose(choices, {
    prompt = "hdlsnip: testbench for",
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
      place_testbench(choice, opts)
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
