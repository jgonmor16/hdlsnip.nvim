--- An in-process LSP server that offers templates as completion items.
---
--- `vim.lsp.start()` accepts `cmd` as a Lua function returning a client, so
--- this is a table rather than a process: no binary, no dependency, no
--- startup cost.
---
--- It is a server rather than a completion source because every frontend
--- already consumes LSP. One implementation covers the built-in menu through
--- `vim.lsp.completion.enable()`, nvim-cmp and blink.cmp, instead of three
--- sources with three sets of bugs. It also composes with `vhdl_ls`: both
--- clients attach to the same buffer and the menu merges them.
---
--- Dynamic templates are offered too. A completion item cannot ask a
--- question, so one of those inserts nothing and the `CompleteDone` handler
--- opens the parameter dialog instead. Offering only static templates would
--- have put one item in the menu out of seventeen.
local config = require("hdlsnip.config")
local registry = require("hdlsnip.registry")
local render = require("hdlsnip.render")

local M = {}

M.name = "hdlsnip"

--- Characters that make Neovim ask for completions.
---
--- Every letter, digit and underscore: triggers are words, so completion has
--- to be offered while one is being typed. An empty list would mean
--- `autotrigger` never fires, since it waits for a trigger character.
local TRIGGER_CHARACTERS = (function()
  local chars = { "_" }
  for byte = string.byte("a"), string.byte("z") do
    chars[#chars + 1] = string.char(byte)
  end
  for digit = 0, 9 do
    chars[#chars + 1] = tostring(digit)
  end
  return chars
end)()

--- Most lines of a template the documentation popup shows.
---
--- The popup opens beside the menu, in whatever room is left. A full FIFO
--- or bus slave runs past a hundred lines, which leaves a narrow strip of
--- wrapped VHDL over the buffer rather than something readable at a glance.
M.PREVIEW_LINES = 15

--- The part of a rendered template worth previewing.
---
--- Starts at the first line of code, skipping the context clause, blank
--- lines and the header comment: they are the same in every template and
--- would otherwise use up most of the lines on offer. Capped at
--- `PREVIEW_LINES`, with a closing comment saying how much was left out.
---@param text string rendered VHDL
---@return string
function M.preview(text)
  local lines = render.lines(text)
  local first = 1
  for index, line in ipairs(lines) do
    local code = vim.trim(line):lower()
    if
      code ~= ""
      and not code:match("^%-%-")
      and not code:match("^library%s")
      and not code:match("^use%s")
    then
      first = index
      break
    end
  end

  local shown = vim.list_slice(lines, first, first + M.PREVIEW_LINES - 1)
  local hidden = #lines - (first - 1) - #shown
  if hidden > 0 then
    shown[#shown + 1] = ("-- ... %d more lines"):format(hidden)
  end
  return table.concat(shown, "\n")
end

--- Completion items for the configuration in effect for a buffer.
---
--- Rendered per request rather than cached, because `.hdlsnip.lua` makes the
--- configuration per project: the same template completes differently in two
--- buffers.
---
--- With `prefix`, only the templates whose trigger starts with it. A client
--- filters the reply against the line as it is when the reply lands, not as
--- it was when it asked: with a slower server on the same buffer, `sig` then
--- ` :` typed quickly leaves nothing to filter by, and every template shown
--- would stay. Filtering against the word the request was made at means
--- such a reply carries nothing that does not match what was typed.
---@param cfg table
---@param prefix string? the word before the cursor
---@return table[]
function M.items(cfg, prefix)
  local kind = vim.lsp.protocol.CompletionItemKind.Snippet
  local items = {}
  prefix = prefix and prefix:lower()

  for _, tpl in ipairs(registry.list({ lang = "vhdl" })) do
    if tpl.trig and (not prefix or vim.startswith(tpl.trig, prefix)) then
      local preview = render.values(tpl, {}, cfg)
      local documentation = preview
          and {
            kind = "markdown",
            value = ("```vhdl\n%s\n```"):format(M.preview(preview)),
          }
        or nil

      if tpl.dynamic then
        -- Nothing is inserted here: CompleteDone opens the dialog, and
        -- inserting text first would have to be undone.
        items[#items + 1] = {
          label = tpl.trig,
          filterText = tpl.trig,
          -- Not a snippet: nothing is inserted and a dialog opens instead.
          -- Frontends draw an icon from the kind, so the two behave
          -- differently and should look different. The kind is the only
          -- mark: a suffix on the detail widened every row of the menu.
          kind = vim.lsp.protocol.CompletionItemKind.Interface,
          detail = tpl.desc,
          insertText = "",
          insertTextFormat = 1,
          documentation = documentation,
          data = { template = tpl.name, dynamic = true },
        }
      else
        local body = render.placeholders(tpl, cfg)
        if body then
          items[#items + 1] = {
            label = tpl.trig,
            filterText = tpl.trig,
            kind = kind,
            detail = tpl.desc,
            insertText = body,
            insertTextFormat = 2, -- snippet
            documentation = documentation,
            data = { template = tpl.name },
          }
        end
      end
    end
  end

  return items
end

--- Buffer a completion request refers to, so the project configuration for
--- that buffer is the one used.
---@param params table
---@return integer
local function buffer_of(params)
  local uri = params and params.textDocument and params.textDocument.uri
  if not uri then
    return vim.api.nvim_get_current_buf()
  end
  return vim.uri_to_bufnr(uri)
end

--- Byte column of a UTF-16 position, on either side of the 0.11 change to
--- `vim.str_byteindex`.
---@param line string
---@param character integer
---@return integer
local function byte_col(line, character)
  if vim.fn.has("nvim-0.11") == 1 then
    return vim.str_byteindex(line, "utf-16", character, false)
  end
  return vim.str_byteindex(line, character, true)
end

--- The word before the position a completion request was made at.
---
--- Triggers are words, so a request with nothing typed -- after whitespace,
--- on an empty line -- cannot be asking for a template. Answering it with
--- every template floods the menu whenever anything asks: 'autocomplete'
--- with "o" in 'complete', or a reply that lands after insert mode was
--- entered again somewhere else on the line.
---@param bufnr integer
---@param position table LSP position, UTF-16 columns
---@return string? word nil when there is none
function M.word_before(bufnr, position)
  local line = vim.api.nvim_buf_get_lines(
    bufnr,
    position.line,
    position.line + 1,
    false
  )[1]
  if not line then
    return nil
  end
  local ok, col = pcall(byte_col, line, position.character)
  return line:sub(1, ok and col or #line):match("[%w_]+$")
end

--- Build the in-process client. Passed to `vim.lsp.start()` as `cmd`.
---@param dispatchers table
---@return table
function M.server(dispatchers)
  local closing = false
  local request_id = 0
  local srv = {}

  function srv.request(method, params, callback)
    -- Deferred on purpose. A real server replies over a socket, so its
    -- handler always runs on a later tick; calling back synchronously runs
    -- the completion handler inside the keypress that triggered the request,
    -- where textlock forbids changing text (E565).
    local function reply(result)
      vim.schedule(function()
        callback(nil, result)
      end)
    end

    if method == "initialize" then
      reply({
        capabilities = {
          completionProvider = { triggerCharacters = TRIGGER_CHARACTERS },
        },
        serverInfo = { name = M.name },
      })
    elseif method == "textDocument/completion" then
      local bufnr = buffer_of(params)
      local word = params.position and M.word_before(bufnr, params.position)
      if params.position and not word then
        reply({})
      else
        local ok, cfg = pcall(config.get, bufnr)
        reply(M.items(ok and cfg or config.get(), word))
      end
    elseif method == "shutdown" then
      reply(nil)
    else
      reply(nil)
    end

    request_id = request_id + 1
    return true, request_id
  end

  function srv.notify(method)
    if method == "exit" then
      dispatchers.on_exit(0, 15)
    end
    return true
  end

  function srv.is_closing()
    return closing
  end

  function srv.terminate()
    closing = true
  end

  return srv
end

--- Finish a completion that only named a template.
---
--- A dynamic template inserts nothing, so accepting one leaves the buffer as
--- it was and this opens the dialog. Read from `v:completed_item`, which is
--- where Neovim keeps the LSP item after the menu closes.
local function completed()
  local item = vim.v.completed_item
  local data = item
    and item.user_data
    and item.user_data.nvim
    and item.user_data.nvim.lsp
    and item.user_data.nvim.lsp.completion_item
  if not data or not data.data or not data.data.dynamic then
    return
  end

  -- Scheduled: CompleteDone fires while the menu is still tearing down, and
  -- opening a window from inside it is not allowed.
  vim.schedule(function()
    require("hdlsnip").insert(data.data.template)
  end)
end

--- Attach the server to a buffer, once.
---@param bufnr integer?
---@return integer? client_id
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = M.name })) do
    return client.id
  end

  vim.api.nvim_create_autocmd("CompleteDone", {
    buffer = bufnr,
    group = vim.api.nvim_create_augroup(
      "hdlsnip.lsp." .. bufnr,
      { clear = true }
    ),
    desc = "hdlsnip: ask for parameters after a dynamic template is chosen",
    callback = completed,
  })

  return vim.lsp.start({
    name = M.name,
    cmd = M.server,
    -- No root_dir: templates come from the runtimepath, not the project, so
    -- there is nothing to find markers for.
  }, { bufnr = bufnr })
end

return M
