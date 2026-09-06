--- Shared test helpers.
local M = {}

--- Run `fn` with `vim.notify` replaced, returning whatever it emitted.
---
--- Without this, a test that exercises a rejection path writes to stderr in
--- headless Neovim, which the parent process reports as an error and which
--- can fail a CI job whose tests all passed.
---@param fn function
---@return table[] notifications each `{ msg = string, level = integer }`
function M.captured_notify(fn)
  local original = vim.notify
  local messages = {}
  vim.notify = function(msg, level)
    messages[#messages + 1] = { msg = msg, level = level }
  end
  local ok, err = pcall(fn)
  vim.notify = original
  assert(ok, err)
  return messages
end

--- Absolute path of the fixture runtimepath entry.
---@return string
function M.fixture_rtp()
  local here = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(here, ":p:h") .. "/fixtures"
end

return M
