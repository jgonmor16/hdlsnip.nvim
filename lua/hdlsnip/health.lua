--- `:checkhealth hdlsnip`.
local M = {}

function M.check()
  local health = vim.health
  health.start("hdlsnip.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10 or newer is required for vim.snippet")
  end

  local registry = require("hdlsnip.registry")
  local list = registry.list()
  local by_kind = {}
  for _, tpl in ipairs(list) do
    by_kind[tpl.kind] = (by_kind[tpl.kind] or 0) + 1
  end

  if #list == 0 then
    health.error("no templates found on the runtimepath")
  else
    local parts = {}
    for kind, count in pairs(by_kind) do
      parts[#parts + 1] = ("%s: %d"):format(kind, count)
    end
    table.sort(parts)
    health.ok(("%d templates (%s)"):format(#list, table.concat(parts, ", ")))
  end

  local problems = registry.problems()
  if #problems == 0 then
    health.ok("every discovered template loaded")
  else
    for _, problem in ipairs(problems) do
      health.warn(problem)
    end
  end

  local config = require("hdlsnip.config")
  local cfg = config.get(0)
  health.info(("VHDL-%s, %s keywords"):format(cfg.vhdl_std, cfg.keyword_case))
  health.info(
    ("clock %s, reset %s %s"):format(
      cfg.clock.name,
      cfg.reset.name,
      cfg.reset.style
    )
  )

  if vim.fn.exists(":LuaSnip") == 2 or package.loaded.luasnip then
    health.info("LuaSnip detected")
  end
end

return M
