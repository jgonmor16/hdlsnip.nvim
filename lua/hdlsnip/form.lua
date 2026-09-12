--- A dialog for a template's parameters.
---
--- One window serves both jobs: entering values before a dynamic template is
--- inserted, and changing them afterwards. Editing the parameters outside the
--- generated code is what keeps this simple -- there is no cursor to preserve
--- in a block being replaced, and no per-parameter region to track.
---
--- Each line is `name` then the value. Only the value is meant to change;
--- a name that stops matching a parameter is reported rather than guessed at.
local edit = require("hdlsnip.edit")
local template = require("hdlsnip.template")
local config = require("hdlsnip.config")

local M = {}

local DEBOUNCE = 150 -- ms of quiet before a live re-render
local NAMESPACE = vim.api.nvim_create_namespace("hdlsnip.form")

local open_form = nil

--- Parse form lines back into raw values, keyed by parameter name.
---@param lines string[]
---@param names table<string, true>
---@return table values
---@return string[] unknown
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

--- The form's contents for a set of parameters and values.
---@param params table[]
---@param values table
---@return string[] lines
---@return integer label_width
function M.lines(params, values)
  local width = 0
  for _, param in ipairs(params or {}) do
    width = math.max(width, #param.name)
  end

  local lines = {}
  for index, param in ipairs(params or {}) do
    lines[index] = ("%-" .. width .. "s  %s"):format(
      param.name,
      tostring(values[param.name])
    )
  end
  return lines, width
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

  local names = {}
  for _, param in ipairs(params) do
    names[param.name] = true
  end

  local lines, label_width = M.lines(params, opts.values)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "hdlsnip-form"

  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  for _, param in ipairs(params) do
    width = math.max(width, label_width + 2 + #M.hint(param) + 2)
  end
  width = math.max(width + 2, #(opts.title or "") + 6, 34)

  local win = vim.api.nvim_open_win(buf, true, {
    -- Bottom right rather than over the code: watching the buffer change is
    -- half the point.
    relative = "editor",
    anchor = "SE",
    row = vim.o.lines - 3,
    col = vim.o.columns - 2,
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = (" %s "):format(opts.title or "parameters"),
    title_pos = "center",
  })
  vim.wo[win].cursorline = true

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
      -- Above the dialog, so it stays on screen whatever the dialog's height.
      row = vim.o.lines - 4 - #lines,
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

  --- Hints sit immediately after the name, as inline virtual text: at the end
  --- of the line they would slide along as the value is typed.
  local function decorate()
    vim.api.nvim_buf_clear_namespace(buf, NAMESPACE, 0, -1)
    for index, param in ipairs(params) do
      vim.api.nvim_buf_set_extmark(buf, NAMESPACE, index - 1, #param.name, {
        virt_text = { { " " .. M.hint(param) .. " ", "Comment" } },
        virt_text_pos = "inline",
      })
    end
  end

  --- Coerce the form's contents. Returns nil and the reasons when a value
  --- does not validate, which is normal while one is being typed.
  local function collect()
    local raw, unknown =
      M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), names)
    if #unknown > 0 then
      return nil, { ("%q is not a parameter"):format(unknown[1]) }
    end

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

  -- At the end of the first value, in insert mode: typing replaces or
  -- extends it without first having to move.
  vim.api.nvim_win_set_cursor(win, { 1, #(lines[1] or "") })
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
