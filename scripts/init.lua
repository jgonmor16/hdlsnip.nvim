-- Runtimepath for scripts run headless (golden rendering, exports).
--
-- Deliberately separate from tests/minimal_init.lua: that one requires
-- plenary and fails without it, which a rendering script has no need for.
local here = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(here, ":p:h:h")

vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
