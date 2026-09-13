--- Re-rendering a template after it has been inserted.
---
--- A dynamic template prompts once and inserts finished code, so changing
--- your mind means deleting the block and starting again. This keeps the
--- block anchored, so its parameters can be changed and the text replaced in
--- place.
---
--- One extmark per block, not one per parameter. We generate the text, so
--- there is nothing to parse and no per-parameter region to track: re-render
--- from the parameters and replace the range. That is what makes this small
--- enough to be worth having.
---
--- The anchor is dropped as soon as it might be wrong -- on write, or when
--- the block no longer matches what was rendered. A stale anchor silently
--- overwriting hand-edited code is the worst failure available here, so it
--- errs toward forgetting.
local config = require("hdlsnip.config")
local render = require("hdlsnip.render")

local M = {}

local namespace = vim.api.nvim_create_namespace("hdlsnip.edit")

--- Tracked blocks, per buffer, keyed by extmark id.
---@type table<integer, table<integer, table>>
local state = {}

local group = vim.api.nvim_create_augroup("hdlsnip.edit", { clear = true })

--- Resolve 0 to the actual buffer number. `state` is keyed by number, so
--- storing under 7 and looking up under 0 would silently miss.
---@param bufnr integer?
---@return integer
local function resolve(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

--- Forget every block in a buffer.
---@param bufnr integer
function M.detach_all(bufnr)
  bufnr = resolve(bufnr)
  if state[bufnr] then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    state[bufnr] = nil
  end
end

--- Forget one block.
---@param bufnr integer
---@param id integer
function M.detach(bufnr, id)
  bufnr = resolve(bufnr)
  if state[bufnr] then
    state[bufnr][id] = nil
    pcall(vim.api.nvim_buf_del_extmark, bufnr, namespace, id)
  end
end

--- Anchor an inserted block so it can be re-rendered.
---
--- Only for a block that was inserted as one range. A `mixed` template goes
--- into two places, and tracking half of it would be worse than tracking
--- none.
---@param bufnr integer
---@param tpl table
---@param params table
---@param first_row integer 1-based, first line of the block
---@param line_count integer
---@return integer? id
function M.track(bufnr, tpl, params, first_row, line_count)
  bufnr = resolve(bufnr)
  if line_count < 1 then
    return nil
  end

  local last_row = first_row + line_count - 1
  local lines =
    vim.api.nvim_buf_get_lines(bufnr, first_row - 1, last_row, false)
  local indent = (lines[1] or ""):match("^%s*")

  local id = vim.api.nvim_buf_set_extmark(bufnr, namespace, first_row - 1, 0, {
    end_row = last_row - 1,
    end_col = #(lines[#lines] or ""),
    -- Both boundaries push outward: text inserted at the first or last
    -- position lands outside the block. Left gravity at the start would keep
    -- the mark put when a line is inserted above it, so the block would
    -- appear to begin at the new line.
    right_gravity = true,
    end_right_gravity = false,
  })

  state[bufnr] = state[bufnr] or {}
  state[bufnr][id] = {
    template = tpl,
    params = vim.deepcopy(params),
    indent = indent,
    rendered = lines,
  }

  vim.api.nvim_create_autocmd({ "BufWritePost", "BufUnload" }, {
    group = group,
    buffer = bufnr,
    desc = "hdlsnip: forget tracked blocks",
    callback = function()
      M.detach_all(bufnr)
    end,
  })

  return id
end

--- The block containing `row`, if any.
---@param bufnr integer
---@param row integer 1-based
---@return integer? id
---@return table? entry
function M.at(bufnr, row)
  bufnr = resolve(bufnr)
  if not state[bufnr] then
    return nil
  end
  for id, entry in pairs(state[bufnr]) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(
      bufnr,
      namespace,
      id,
      { details = true }
    )
    if mark and mark[1] then
      local first = mark[1] + 1
      local last = (mark[3] and mark[3].end_row or mark[1]) + 1
      if row >= first and row <= last then
        return id, entry
      end
    end
  end
  return nil
end

--- Parameters a tracked block was rendered with.
---@param bufnr integer
---@param id integer
---@return table?
function M.params(bufnr, id)
  bufnr = resolve(bufnr)
  local entry = state[bufnr] and state[bufnr][id]
  return entry and vim.deepcopy(entry.params) or nil
end

--- Re-render a tracked block with changed parameters.
---
--- Invalid input is normal while a value is being typed -- `2` on the way to
--- `23` -- so a rejected change leaves the buffer alone and reports instead.
---@param bufnr integer
---@param id integer
---@param changes table<string, any>
---@return boolean ok
---@return string[] errors
function M.update(bufnr, id, changes)
  bufnr = resolve(bufnr)
  local entry = state[bufnr] and state[bufnr][id]
  if not entry then
    return false, { "block is no longer tracked" }
  end

  local mark =
    vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, id, { details = true })
  if not mark or not mark[1] then
    M.detach(bufnr, id)
    return false, { "anchor lost" }
  end

  local first = mark[1]
  local last = (mark[3] and mark[3].end_row or mark[1])

  -- If the block no longer matches what was rendered, it has been edited by
  -- hand. Replacing it would throw that work away.
  local current = vim.api.nvim_buf_get_lines(bufnr, first, last + 1, false)
  if not vim.deep_equal(current, entry.rendered) then
    M.detach(bufnr, id)
    return false, { "block was edited by hand, so it is no longer tracked" }
  end

  local params = vim.tbl_extend("force", entry.params, changes or {})
  local sections, errors =
    render.sections(entry.template, params, config.get(bufnr))
  if not sections then
    return false, errors
  end
  if sections.declarations and sections.declarations ~= "" then
    return false, { "a template with declarations is not tracked" }
  end

  local lines = {}
  for _, line in ipairs(render.lines(sections.statements or "")) do
    lines[#lines + 1] = line == "" and "" or (entry.indent .. line)
  end

  vim.api.nvim_buf_set_lines(bufnr, first, last + 1, false, lines)
  vim.api.nvim_buf_set_extmark(bufnr, namespace, first, 0, {
    id = id,
    end_row = first + #lines - 1,
    end_col = #(lines[#lines] or ""),
    right_gravity = true,
    end_right_gravity = false,
  })

  entry.params = params
  entry.rendered = lines
  return true, {}
end

return M
