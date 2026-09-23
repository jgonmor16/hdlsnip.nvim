--- A dialog for a template's parameters.
---
--- One window serves both jobs: entering values before a dynamic template is
--- inserted, and changing them afterwards. Editing the parameters outside the
--- generated code is what keeps this simple -- there is no cursor to preserve
--- in a block being replaced, and no per-parameter region to track.
---
--- Each line holds one parameter's value and nothing else. The name and the
--- hint beside it are virtual text, so there is no label to delete by
--- accident: `<C-u>` on a field clears the field, not the parameter it names.
local edit = require("hdlsnip.edit")
local template = require("hdlsnip.template")
local config = require("hdlsnip.config")

local M = {}

local DEBOUNCE = 150 -- ms of quiet before a live re-render
local NAMESPACE = vim.api.nvim_create_namespace("hdlsnip.form")

local open_form = nil

--- Read the form's lines back as raw values, keyed by parameter name.
---
--- By position: line N is parameter N, because the buffer holds the values
--- and nothing else.
---@param lines string[]
---@param params table[]
---@return table values
function M.parse(lines, params)
  local values = {}
  for index, param in ipairs(params or {}) do
    values[param.name] = vim.trim(lines[index] or "")
  end
  return values
end

--- The form's contents: one value per line, in parameter order.
---@param params table[]
---@param values table
---@return string[] lines
function M.lines(params, values)
  local lines = {}
  for index, param in ipairs(params or {}) do
    lines[index] = tostring(values[param.name])
  end
  return lines
end

--- The dialog's inner width, and where the value column starts.
---
--- Separate from `M.open` so the arithmetic can be checked without a window.
--- `prefix` is the width of the inline virtual text on each row: columns the
--- buffer line knows nothing about. Sizing from the buffer line alone wraps
--- the longest row, which breaks the border and costs a parameter its place.
---@param params table[]
---@param lines string[]
---@param title string?
---@return table `{ width, prefix, label_width, hint_width }`
function M.geometry(params, lines, title)
  local label_width, hint_width = 0, 0
  for _, param in ipairs(params or {}) do
    label_width = math.max(label_width, #param.name)
    hint_width = math.max(hint_width, #M.hint(param))
  end
  -- Name, a space, the hint, then the gap before the value: all of it
  -- virtual text, and none of it in the buffer line.
  local prefix = label_width + hint_width + 4

  local width = 0
  for _, line in ipairs(lines or {}) do
    width = math.max(width, prefix + #line)
  end

  return {
    width = math.max(width + 2, #(title or "") + 6, 34),
    prefix = prefix,
    label_width = label_width,
    hint_width = hint_width,
  }
end

--- What a field accepts, shown beside it.
---@param param table
---@return string
function M.hint(param)
  if param.type == "choice" then
    return table.concat(param.choices, " | ")
  end
  if param.min or param.max then
    return ("%s %s..%s"):format(param.type, param.min or "", param.max or "")
  end
  return param.type
end

--- Close the dialog.
function M.close()
  local current = open_form
  open_form = nil
  if current then
    M.close_window(current.win)
  end
end

--- Close a specific window, whatever the shared state says.
---@param win integer
function M.close_window(win)
  open_form = nil
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

--- Open the dialog.
---
--- `on_change` is optional: with it the values are coerced and handed over on
--- every pause in typing, which is what live editing uses. Without it, the
--- values are only checked when the dialog is accepted.
---@param opts table `{ title, params, values, cfg, on_change, on_accept }`
---@return boolean opened
function M.open(opts)
  M.close()

  local params = opts.params or {}
  if #params == 0 then
    opts.on_accept({})
    return false
  end

  local lines = M.lines(params, opts.values)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "hdlsnip-form"

  local geometry = M.geometry(params, lines, opts.title)
  local label_width, hint_width = geometry.label_width, geometry.hint_width
  -- The clamp stays here rather than inside M.geometry: the screen is not
  -- something the arithmetic should have to know about to be testable.
  local width = math.min(geometry.width, vim.o.columns - 4)

  local win = vim.api.nvim_open_win(buf, true, {
    -- Bottom right rather than over the code: watching the buffer change is
    -- half the point.
    relative = "editor",
    anchor = "SE",
    -- One line above the command line, so it sits at the bottom of the
    -- window rather than floating in the middle of the code.
    row = vim.o.lines - 1,
    col = vim.o.columns - 2,
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = (" %s "):format(opts.title or "parameters"),
    title_pos = "center",
  })
  vim.wo[win].cursorline = true
  -- Backstop for a value still too long once the width is clamped: scrolling
  -- keeps the border intact, wrapping does not.
  vim.wo[win].wrap = false

  local origin = opts.origin_win
  open_form = { win = win, buf = buf }

  local error_win, error_buf

  --- Show the reasons a value was rejected, in their own window above the
  --- dialog. Virtual text on the first line competed with the hints and was
  --- easy to miss entirely.
  local function show_errors(errors)
    if not errors or #errors == 0 then
      if error_win and vim.api.nvim_win_is_valid(error_win) then
        vim.api.nvim_win_close(error_win, true)
      end
      error_win = nil
      return
    end

    if not (error_buf and vim.api.nvim_buf_is_valid(error_buf)) then
      error_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[error_buf].buftype = "nofile"
      vim.bo[error_buf].bufhidden = "wipe"
    end
    vim.api.nvim_buf_set_lines(error_buf, 0, -1, false, errors)

    local error_width = 0
    for _, line in ipairs(errors) do
      error_width = math.max(error_width, #line)
    end
    error_width = math.max(error_width + 2, width)

    local window = {
      relative = "editor",
      anchor = "SE",
      -- Clear of the dialog's own top border. With anchor "SE" the dialog
      -- ends at `vim.o.lines - 1` and is #lines tall plus two border rows, so
      -- anything below this covers its title.
      row = vim.o.lines - 1 - #lines - 2,
      col = vim.o.columns - 2,
      width = error_width,
      height = #errors,
      style = "minimal",
      border = "rounded",
      focusable = false,
      zindex = 60,
    }

    if error_win and vim.api.nvim_win_is_valid(error_win) then
      vim.api.nvim_win_set_config(error_win, window)
    else
      error_win = vim.api.nvim_open_win(error_buf, false, window)
      vim.wo[error_win].winhighlight = "Normal:ErrorMsg,FloatBorder:ErrorMsg"
    end
  end

  local timer = assert(vim.uv.new_timer())
  local timer_closed = false
  local function stop_timer()
    if not timer_closed then
      timer_closed = true
      timer:stop()
      timer:close()
    end
  end

  --- Name and hint are inline virtual text at the head of the line, so the
  --- buffer holds only what the user is meant to change. Left gravity keeps
  --- them put when the value is edited from column zero.
  local function decorate()
    vim.api.nvim_buf_clear_namespace(buf, NAMESPACE, 0, -1)
    for index, param in ipairs(params) do
      vim.api.nvim_buf_set_extmark(buf, NAMESPACE, index - 1, 0, {
        virt_text = {
          { ("%-" .. label_width .. "s "):format(param.name), "Identifier" },
          { ("%-" .. hint_width .. "s   "):format(M.hint(param)), "Comment" },
        },
        virt_text_pos = "inline",
        right_gravity = false,
      })
    end
  end

  --- Coerce the form's contents. Returns nil and the reasons when a value
  --- does not validate, which is normal while one is being typed.
  local function collect()
    local buffer_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- Deleting a whole line would shift every value onto the wrong
    -- parameter, which is worse than any wrong value. Fail loudly instead.
    if #buffer_lines ~= #params then
      return nil, { "a field was added or removed; press Esc and reopen" }
    end

    local raw = M.parse(buffer_lines, params)
    local values, errors = {}, {}
    for _, param in ipairs(params) do
      local value, err = template.coerce(param, raw[param.name], opts.cfg)
      if err then
        errors[#errors + 1] = ("%s: %s"):format(param.name, err)
      else
        values[param.name] = value
      end
    end
    if #errors > 0 then
      return nil, errors
    end
    return values, {}
  end

  decorate()
  show_errors(nil)

  if opts.on_change then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = buf,
      desc = "hdlsnip: re-render as the dialog is edited",
      callback = function()
        timer:stop()
        timer:start(
          DEBOUNCE,
          0,
          vim.schedule_wrap(function()
            if not vim.api.nvim_buf_is_valid(buf) then
              return
            end
            local values, errors = collect()
            show_errors(values and opts.on_change(values) or errors)
          end)
        )
      end,
    })
  end

  vim.api.nvim_create_autocmd({ "BufLeave", "WinClosed" }, {
    buffer = buf,
    once = true,
    callback = function()
      stop_timer()
      show_errors(nil)
      open_form = nil
    end,
  })

  local function accept()
    vim.cmd.stopinsert()
    local values, errors = collect()
    if not values then
      show_errors(errors)
      return
    end
    show_errors(nil)
    M.close_window(win)
    if origin and vim.api.nvim_win_is_valid(origin) then
      vim.api.nvim_set_current_win(origin)
    end
    if opts.on_accept then
      opts.on_accept(values)
    end
  end

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      M.close_window(win)
      if origin and vim.api.nvim_win_is_valid(origin) then
        vim.api.nvim_set_current_win(origin)
      end
    end, { buffer = buf, nowait = true })
  end
  vim.keymap.set({ "n", "i" }, "<CR>", accept, { buffer = buf })

  --- Move between fields, landing at the end of the value.
  ---
  --- Tab inside this window only. It is the conventional key for moving
  --- through a form, and nothing else in the dialog wants it.
  local function goto_field(delta)
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local target = math.max(1, math.min(#params, row + delta))
    local line = vim.api.nvim_buf_get_lines(buf, target - 1, target, false)[1]
    vim.api.nvim_win_set_cursor(win, { target, #(line or "") })
  end

  --- Accepts one mapping or a list, so a user can keep both Tab and their
  --- own key without choosing.
  local function map_field(setting, delta)
    if not setting then
      return
    end
    local keys = type(setting) == "table" and setting or { setting }
    for _, key in ipairs(keys) do
      vim.keymap.set({ "n", "i" }, key, function()
        goto_field(delta)
      end, { buffer = buf, nowait = true })
    end
  end

  local configured = (opts.cfg and opts.cfg.keys) or {}
  map_field(configured.field_next or { "<Tab>", "<C-k>" }, 1)
  map_field(configured.field_prev or { "<S-Tab>", "<C-j>" }, -1)

  -- At the end of the first value, in insert mode: typing replaces or
  -- extends it without first having to move.
  vim.api.nvim_win_set_cursor(win, { 1, #(lines[1] or "") })
  vim.cmd.startinsert({ bang = true })
  return true
end

--- Choose from a list, by typing to narrow it.
---
--- Two windows, matching the parameter dialog: the choices above, a field
--- below. Typing filters and renumbers, so the numbers are there to count by
--- rather than to address -- a digit narrows like any other character, which
--- is what lets `fifo_2` be typed at all.
---
--- Tab and C-k move down the choices, S-Tab and C-j up, CR takes the
--- highlighted one, and Esc or q cancels. The same keys as the dialog, doing
--- the same thing to a list.
---@param items table[]
---@param opts table `{ prompt, format_item, cfg }`
---@param on_choice fun(item: table?)
function M.select(items, opts, on_choice)
  M.close()

  local format = opts.format_item or tostring

  local labels = {}
  for index, item in ipairs(items) do
    labels[index] = format(item)
  end

  local origin = vim.api.nvim_get_current_win()
  -- `selected` indexes `matches`; `offset` is the first line on screen. The
  -- list scrolls rather than growing, so a project with forty entities does
  -- not cover the code the choice is about to go into.
  local matches, selected, offset = {}, 1, 1

  -- Sized once from the widest entry, so the windows do not resize while
  -- typing, which reads as flicker.
  local width = #(opts.prompt or "") + 6
  for _, label in ipairs(labels) do
    width = math.max(width, #label + 6)
  end
  width = math.max(width, 34)

  local configured_height = (opts.cfg and opts.cfg.picker_height) or 10
  -- Never taller than a third of the screen, whatever the configuration says.
  local visible = math.max(1, math.min(configured_height, vim.o.lines - 6))

  local list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[list_buf].buftype = "nofile"

  vim.bo[list_buf].bufhidden = "wipe"

  local field_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[field_buf].buftype = "nofile"
  vim.bo[field_buf].bufhidden = "wipe"
  vim.bo[field_buf].filetype = "hdlsnip-select"

  local field_win = vim.api.nvim_open_win(field_buf, true, {
    relative = "editor",
    anchor = "SE",
    row = vim.o.lines - 2,
    col = vim.o.columns - 2,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
  })

  local list_win = vim.api.nvim_open_win(list_buf, false, {
    relative = "editor",
    anchor = "SE",
    row = vim.o.lines - 5,
    col = vim.o.columns - 2,
    width = width,
    height = math.max(1, math.min(visible, #labels)),
    style = "minimal",
    border = "rounded",
    title = (" %s "):format(opts.prompt or "select"),
    title_pos = "center",
    focusable = false,
  })
  vim.wo[list_win].cursorline = true

  open_form = { win = field_win, buf = field_buf }

  local function close(item)
    if vim.api.nvim_win_is_valid(list_win) then
      vim.api.nvim_win_close(list_win, true)
    end

    M.close_window(field_win)
    if origin and vim.api.nvim_win_is_valid(origin) then
      vim.api.nvim_set_current_win(origin)
    end
    on_choice(item)
  end

  --- Draw the visible slice, and put the cursor on the selection.
  local function draw()
    -- Constant height, so the window does not jump when the last page is
    -- short or the filter narrows.
    local height = math.max(1, math.min(visible, #matches))
    local lines = {}

    for row = 1, height do
      local match = matches[offset + row - 1]
      -- Numbered by position in the filtered list, so what is on screen
      -- reads 1..n rather than jumping when it scrolls.
      lines[row] = match and ("%2d  %s"):format(offset + row - 1, match.label)
        or ""
    end
    if #matches == 0 then
      lines = { "  no match" }
    end

    vim.bo[list_buf].modifiable = true
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
    vim.bo[list_buf].modifiable = false

    if vim.api.nvim_win_is_valid(list_win) then
      vim.api.nvim_win_set_config(list_win, {
        relative = "editor",
        anchor = "SE",
        row = vim.o.lines - 5,
        col = vim.o.columns - 2,
        width = width,
        height = #lines,
      })
      if #matches > 0 then
        vim.api.nvim_win_set_cursor(list_win, { selected - offset + 1, 0 })
      end
    end
  end

  --- Redraw for the current filter, from the top.
  local function refresh()
    local filter = (vim.api.nvim_buf_get_lines(field_buf, 0, 1, false)[1] or ""):lower()

    matches = {}
    for index, label in ipairs(labels) do
      if filter == "" or label:lower():find(filter, 1, true) then
        matches[#matches + 1] = { index = index, label = label }
      end
    end

    -- Back to the top on every change: keeping the selection where it was
    -- can leave it on something the filter has just hidden.
    selected, offset = 1, 1
    draw()
  end

  --- Move the selection, scrolling when it would leave the window.
  local function move(delta)
    if #matches == 0 then
      return
    end
    selected = math.max(1, math.min(#matches, selected + delta))
    if selected < offset then
      offset = selected
    elseif selected >= offset + visible then
      offset = selected - visible + 1
    end
    draw()
  end

  local function accept()
    -- Nothing to take is not the same as cancelling, which is what Esc does.
    if #matches == 0 then
      return
    end
    vim.cmd.stopinsert()
    close(items[matches[selected].index])
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = field_buf,
    desc = "hdlsnip: narrow the choices",
    callback = refresh,
  })

  vim.keymap.set({ "n", "i" }, "<CR>", accept, { buffer = field_buf })
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      close(nil)
    end, { buffer = field_buf, nowait = true })
  end

  local configured = (opts.cfg and opts.cfg.keys) or {}
  local function map_move(setting, fallback, delta)
    local keys = setting or fallback
    if not keys then
      return
    end
    for _, key in ipairs(type(keys) == "table" and keys or { keys }) do
      vim.keymap.set({ "n", "i" }, key, function()
        move(delta)
      end, { buffer = field_buf, nowait = true })
    end
  end
  map_move(configured.field_next, { "<Tab>", "<C-k>" }, 1)
  map_move(configured.field_prev, { "<S-Tab>", "<C-j>" }, -1)

  --- Move a whole page, landing on its first entry.
  ---
  --- The page boundary is what moved, so keeping the selection at the same
  --- screen row would land it somewhere arbitrary. The top of the new page
  --- is predictable.
  ---
  --- Wraps: with three pages, paging past the last returns to the first.
  --- Clamping would leave the key doing nothing, and a short list has no
  --- meaningful end to stop at.
  local function page(direction)
    if #matches == 0 then
      return
    end
    local pages = math.ceil(#matches / visible)
    local current = math.floor((offset - 1) / visible)
    -- Modulo over the page index rather than the offset, so the last page
    -- being short does not shift every boundary.
    local next_page = (current + direction) % pages
    offset = next_page * visible + 1
    selected = offset
    draw()
  end

  for key, direction in pairs({ ["<C-d>"] = 1, ["<C-u>"] = -1 }) do
    vim.keymap.set({ "n", "i" }, key, function()
      page(direction)
    end, { buffer = field_buf, nowait = true })
  end

  refresh()
  vim.cmd.startinsert({ bang = true })
  return true
end

--- Ask for a template's parameters before inserting it.
---@param tpl table
---@param cfg table
---@param on_accept fun(values: table)
function M.prompt(tpl, cfg, on_accept)
  local values = {}
  for _, param in ipairs(tpl.params or {}) do
    values[param.name] = param.default
  end

  M.open({
    title = tpl.name,
    params = tpl.params,
    values = values,
    cfg = cfg,
    origin_win = vim.api.nvim_get_current_win(),
    on_accept = on_accept,
  })
end

--- Change the parameters of the tracked block under the cursor.
---@param bufnr integer?
---@return boolean opened
function M.edit(bufnr)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local id, entry = edit.at(bufnr, row)
  if not id then
    vim.notify("hdlsnip: no template under the cursor", vim.log.levels.WARN)
    return false
  end

  return M.open({
    title = entry.template.name,
    params = entry.template.params,
    values = entry.params,
    cfg = config.get(bufnr),
    origin_win = vim.api.nvim_get_current_win(),
    on_change = function(values)
      local ok, errors = edit.update(bufnr, id, values)
      return ok and {} or errors
    end,
    on_accept = function(values)
      edit.update(bufnr, id, values)
    end,
  })
end

return M
