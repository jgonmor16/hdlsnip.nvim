--- Finding where in an architecture a fragment belongs.
---
--- A `mixed` template emits declarations and statements, which go either side
--- of `begin`. Putting both at the cursor puts the declarations somewhere
--- they are not legal, so the enclosing architecture has to be found first.
---
--- Deliberately a line scan rather than treesitter. Neovim ships no VHDL
--- parser, so a treesitter implementation would work only for users who have
--- installed one, and this plugin otherwise needs nothing. The scan is
--- heuristic and says so: when it is unsure it reports nothing and the caller
--- falls back to inserting at the cursor.
local M = {}

--- Indentation width of a line, in characters.
---@param line string
---@return integer
local function indent_of(line)
  return #(line:match("^%s*") or "")
end

--- True when `line` opens an architecture body.
---@param line string
---@return boolean
local function is_architecture(line)
  return line:lower():match("^%s*architecture%s+[%w_]+%s+of%s+") ~= nil
end

--- True when `line` closes an architecture with the keyword spelled out.
---
--- Used when scanning upward, where a loose match would treat `end process`
--- as the end of the architecture and give up while still inside it.
---@param line string
---@return boolean
local function closes_architecture(line)
  return line:lower():match("^%s*end%s+architecture") ~= nil
end

--- True when `line` could close an architecture, including the short forms.
--- Only trusted at the architecture's own indentation.
---@param line string
---@return boolean
local function is_architecture_end(line)
  local lowered = line:lower()
  return closes_architecture(line)
    or lowered:match("^%s*end%s*;") ~= nil
    or lowered:match("^%s*end%s+[%w_]+%s*;") ~= nil
end

--- The architecture surrounding `row`, if there is one.
---
--- The `begin` that closes the declarative part is found by indentation: a
--- `begin` belonging to a function or procedure in the declarative part is
--- indented further than the architecture keyword, and the architecture's own
--- `begin` is not. That holds for every VHDL style in common use, and when it
--- does not the result is no worse than inserting at the cursor.
---@param bufnr integer
---@param row integer 1-based
---@return table? `{ architecture, begin_row, end_row }`, all 1-based
function M.architecture(bufnr, row)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 then
    return nil
  end
  row = math.min(math.max(row, 1), #lines)

  local start
  for index = row, 1, -1 do
    if is_architecture(lines[index]) then
      start = index
      break
    end
    -- An `end architecture` above the cursor means the cursor is between two
    -- architectures, not inside the earlier one.
    if index < row and closes_architecture(lines[index]) then
      return nil
    end
  end
  if not start then
    return nil
  end

  local base = indent_of(lines[start])

  local begin_row
  for index = start + 1, #lines do
    local line = lines[index]
    if line:lower():match("^%s*begin%s*$") and indent_of(line) <= base then
      begin_row = index
      break
    end
  end
  if not begin_row then
    return nil
  end

  local end_row
  for index = begin_row + 1, #lines do
    if
      is_architecture_end(lines[index]) and indent_of(lines[index]) <= base
    then
      end_row = index
      break
    end
  end
  if not end_row or row > end_row then
    return nil
  end

  return { architecture = start, begin_row = begin_row, end_row = end_row }
end

return M
