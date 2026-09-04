--- Putting rendered text into a buffer.
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
  return from + 1
end

return M
