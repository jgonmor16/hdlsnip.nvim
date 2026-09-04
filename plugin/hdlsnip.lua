-- User commands.
--
-- Defined here rather than in setup(), so :HdlSnip works on a default
-- configuration without the user having to call anything. The modules
-- themselves are required lazily inside the callbacks, which keeps startup
-- cost at zero for anyone who never opens a VHDL file.
if vim.g.loaded_hdlsnip then
  return
end
vim.g.loaded_hdlsnip = true

local function complete(lead)
  return vim.tbl_filter(function(name)
    return name:find(lead, 1, true) == 1
  end, require("hdlsnip.registry").names())
end

vim.api.nvim_create_user_command("HdlSnip", function(cmd)
  require("hdlsnip").insert(cmd.args ~= "" and cmd.args or nil)
end, {
  nargs = "?",
  complete = complete,
  desc = "Insert a VHDL template, prompting for its parameters",
})

vim.api.nvim_create_user_command("HdlSnipExpand", function(cmd)
  require("hdlsnip").expand(cmd.args ~= "" and cmd.args or nil)
end, {
  nargs = "?",
  complete = complete,
  desc = "Expand a VHDL template as a snippet",
})

vim.api.nvim_create_user_command("HdlSnipReload", function()
  require("hdlsnip").reload()
end, { desc = "Rescan the runtimepath for templates" })
