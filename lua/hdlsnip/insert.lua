--- Putting rendered text into a buffer.
local placement = require("hdlsnip.placement")
local render = require("hdlsnip.render")

local M = {}

--- Indentation of a line, as a string.
---@param bufnr integer
---@param row integer 1-based
---@return string
local function indent_of(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  return line:match("^%s*")
end

--- Insert lines at the cursor, indented to match it.
---
--- A blank current line is replaced rather than pushed down: inserting an
--- entity skeleton on the empty first line of a new file should not leave a
--- stray blank line above it. A line with content on it is kept, and the
--- template goes below.
---
--- Blank lines in the template stay empty rather than becoming a run of
--- spaces, so nothing arrives with trailing whitespace.
---@param bufnr integer
---@param lines string[]
---@return integer first_row 1-based row of the first inserted line
---@return integer count how many lines were written
function M.insert_lines(bufnr, lines)
  local win = vim.api.nvim_get_current_win()
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local current = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
    or ""
  local indent = indent_of(bufnr, row)

  local prefixed = {}
  for i, line in ipairs(lines) do
    prefixed[i] = line ~= "" and (indent .. line) or ""
  end

  local blank = current:match("^%s*$") ~= nil
  local from = blank and (row - 1) or row
  local to = blank and row or row

  vim.api.nvim_buf_set_lines(bufnr, from, to, false, prefixed)
  vim.api.nvim_win_set_cursor(win, { from + 1, #indent })
  return from + 1, #prefixed
end

--- Insert a rendered template, placing each half where it is legal.
---
--- A `mixed` template emits declarations and statements, which go either side
--- of the architecture's `begin`. When the enclosing architecture cannot be
--- identified, both halves go in at the cursor as one block: wrong, but no
--- more wrong than before, and the user can see it and move it.
---@param bufnr integer
---@param sections table `{ declarations = string?, statements = string }`
---@param cfg table
---@return boolean placed true when the halves went to separate places
---@return integer? first_row when it went in as one block
---@return integer? count
function M.insert_sections(bufnr, sections, cfg)
  local declarations = sections.declarations or ""
  if declarations == "" then
    local first, count =
      M.insert_lines(bufnr, render.lines(sections.statements or ""))
    return false, first, count
  end

  local win = vim.api.nvim_get_current_win()
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local found = placement.architecture(bufnr, row)

  if not found then
    local both = render.lines(declarations)
    both[#both + 1] = ""
    vim.list_extend(both, render.lines(sections.statements or ""))
    M.insert_lines(bufnr, both)
    return false
  end

  local indent = cfg and cfg.indent or "  "

  local function indented(text)
    local out = {}
    for _, line in ipairs(render.lines(text)) do
      out[#out + 1] = line == "" and "" or (indent .. line)
    end
    return out
  end

  -- Statements first: inserting the declarations would shift every row below
  -- them, including the one the statements are measured against.
  local statements = indented(sections.statements or "")
  statements[#statements + 1] = ""
  vim.api.nvim_buf_set_lines(
    bufnr,
    found.begin_row,
    found.begin_row,
    false,
    statements
  )

  local declaration_lines = indented(declarations)
  declaration_lines[#declaration_lines + 1] = ""
  vim.api.nvim_buf_set_lines(
    bufnr,
    found.begin_row - 1,
    found.begin_row - 1,
    false,
    declaration_lines
  )

  vim.api.nvim_win_set_cursor(win, { found.begin_row, #indent })
  return true
end

return M
