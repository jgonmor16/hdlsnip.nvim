--- A form for editing a tracked block's parameters.
---
--- The parameters are edited outside the generated code rather than inside
--- it. That avoids the hard part of live editing entirely: there is no cursor
--- to preserve in a block that is being replaced, and no per-parameter region
--- to track. Type in the form, watch the block re-render.
---
--- Each line is `name` then the value. Only the value is meant to be edited;
--- changing a name simply stops that line matching a parameter, which is
--- reported rather than guessed at.
local edit = require("hdlsnip.edit")

local M = {}

local DEBOUNCE = 150 -- ms of quiet before re-rendering

--- Parse form lines back into parameter values.
---
--- Kept separate from the window so it can be tested without one.
---@param lines string[]
---@param names table<string, true> parameter names the template declares
---@return table values
---@return string[] unknown names that matched no parameter
function M.parse(lines, names)
  local values, unknown = {}, {}
  for _, line in ipairs(lines) do
    local name, value = line:match("^%s*([%w_]+)%s%s+(.-)%s*$")
    if name then
      if names[name] then
        values[name] = value
      else
        unknown[#unknown + 1] = name
      end
    end
  end
  return values, unknown
end

--- Render the form's contents for a template and its current values.
---@param tpl table
---@param params table
---@return string[] lines
---@return integer width
function M.lines(tpl, params)
  local width = 0
  for _, param in ipairs(tpl.params or {}) do
    width = math.max(width, #param.name)
  end

  local lines = {}
  for _, param in ipairs(tpl.params or {}) do
    lines[#lines + 1] = ("%-" .. width .. "s  %s"):format(
      param.name,
      tostring(params[param.name])
    )
  end
  return lines, width
end

--- Hint shown under a field: its type, and its bounds or choices.
---@param param table
---@return string
function M.hint(param)
  if param.type == "choice" then
    return table.concat(param.choices, " | ")
  end
  if param.min or param.max then
    return ("%s, %s to %s"):format(
      param.type,
      param.min or "any",
      param.max or "any"
    )
  end
  return param.type
end

local open_form = nil

--- Close the form, if one is open.
function M.close()
  local current = open_form
  open_form = nil
  if current then
    M.close_window(current.win)
  end
end

--- Close a specific window, whatever the shared state says.
---
--- The mappings use this rather than `close()`: BufLeave clears `open_form`
--- whenever focus leaves the form, even briefly, and a close that depended on
--- that state would then do nothing at all.
---@param win integer
function M.close_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  open_form = nil
end

--- Open the form for the tracked block under the cursor.
---@param bufnr integer?
---@return boolean opened
function M.open(bufnr)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local id, entry = edit.at(bufnr, row)
  if not id then
    vim.notify(
      "hdlsnip: no template under the cursor to edit",
      vim.log.levels.WARN
    )
    return false
  end

  M.close()

  local tpl = entry.template
  local names = {}
  for _, param in ipairs(tpl.params or {}) do
    names[param.name] = true
  end

  local lines = M.lines(tpl, entry.params)
  local form = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(form, 0, -1, false, lines)
  vim.bo[form].buftype = "nofile"
  vim.bo[form].bufhidden = "wipe"
  vim.bo[form].filetype = "hdlsnip-form"

  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  width = math.max(width + 4, #tpl.name + 8, 32)

  local win = vim.api.nvim_open_win(form, true, {
    -- Bottom right of the editor, not over the block: the point is to watch
    -- the code change while typing.
    relative = "editor",
    anchor = "SE",
    row = vim.o.lines - 3,
    col = vim.o.columns - 2,
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = (" %s "):format(tpl.name),
    title_pos = "center",
  })

  open_form = { win = win, buf = form, target = bufnr, id = id }

  local timer = assert(vim.uv.new_timer())
  local timer_closed = false

  --- uv reports `is_closing` too late when two events arrive from the same
  --- window close, so the flag is ours rather than the handle's.
  local function stop_timer()
    timer_closed = true
    timer:stop()
    timer:close()
  end
  local namespace = vim.api.nvim_create_namespace("hdlsnip.form")

  local function apply()
    if not vim.api.nvim_buf_is_valid(form) then
      return
    end
    vim.api.nvim_buf_clear_namespace(form, namespace, 0, -1)

    local values, unknown =
      M.parse(vim.api.nvim_buf_get_lines(form, 0, -1, false), names)
    if #unknown > 0 then
      vim.api.nvim_buf_set_extmark(form, namespace, 0, 0, {
        virt_text = { { " not a parameter: " .. unknown[1], "WarningMsg" } },
        virt_text_pos = "eol",
      })
      return
    end

    local ok, errors = edit.update(bufnr, id, values)
    if not ok then
      -- Invalid input is normal while a value is being typed, so it is shown
      -- beside the field rather than thrown as an error.
      vim.api.nvim_buf_set_extmark(form, namespace, 0, 0, {
        virt_text = { { " " .. (errors[1] or "invalid"), "WarningMsg" } },
        virt_text_pos = "eol",
      })
    end
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = form,
    desc = "hdlsnip: re-render as the form is edited",
    callback = function()
      timer:stop()
      timer:start(DEBOUNCE, 0, vim.schedule_wrap(apply))
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "WinClosed" }, {
    buffer = form,
    once = true,
    callback = function()
      if timer_closed then
        return
      end
      stop_timer()
      open_form = nil
    end,
  })

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      M.close_window(win)
    end, { buffer = form, nowait = true })
  end
  vim.keymap.set({ "n", "i" }, "<CR>", function()
    vim.cmd.stopinsert()
    apply()
    M.close_window(win)
  end, { buffer = form })

  -- Start on the first value rather than at column zero, which is where the
  -- user is going to type anyway.
  local _, label_width = M.lines(tpl, entry.params)
  vim.api.nvim_win_set_cursor(win, { 1, label_width + 2 })

  return true
end

return M
