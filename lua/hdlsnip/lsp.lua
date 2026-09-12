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

--- Completion items for the configuration in effect for a buffer.
---
--- Rendered per request rather than cached, because `.hdlsnip.lua` makes the
--- configuration per project: the same template completes differently in two
--- buffers.
---@param cfg table
---@return table[]
function M.items(cfg)
  local kind = vim.lsp.protocol.CompletionItemKind.Snippet
  local items = {}

  for _, tpl in ipairs(registry.list({ lang = "vhdl" })) do
    if tpl.trig then
      local preview = render.values(tpl, {}, cfg)
      local documentation = preview
          and {
            kind = "markdown",
            value = ("```vhdl\n%s\n```"):format(preview),
          }
        or nil

      if tpl.dynamic then
        -- Nothing is inserted here: CompleteDone opens the dialog, and
        -- inserting text first would have to be undone.
        items[#items + 1] = {
          label = tpl.trig,
          filterText = tpl.trig,
          kind = kind,
          detail = tpl.desc .. "  (asks for parameters)",
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
      local ok, cfg = pcall(config.get, bufnr)
      reply(M.items(ok and cfg or config.get()))
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
