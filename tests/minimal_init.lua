-- Minimal runtimepath for headless test runs: this plugin plus plenary.
local here = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(here, ":p:h:h")
local plenary = root .. "/.tests/plenary.nvim"

if vim.fn.isdirectory(plenary) == 0 then
  error(
    ("hdlsnip tests: plenary not found at %s -- run `make test`"):format(
      plenary
    )
  )
end

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(plenary)
vim.opt.swapfile = false

-- Lets spec files require shared helpers by name.
package.path = root .. "/tests/?.lua;" .. package.path

vim.cmd("runtime plugin/plenary.vim")
