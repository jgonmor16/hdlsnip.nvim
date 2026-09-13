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

vim.api.nvim_create_user_command("HdlSnipInstantiate", function(cmd)
  require("hdlsnip.instantiate").instantiate(
    cmd.args ~= "" and cmd.args or nil,
    { signals = cmd.bang }
  )
end, {
  nargs = "?",
  bang = true,
  complete = function(lead)
    return vim.tbl_filter(function(name)
      return name:find(lead, 1, true) == 1
    end, require("hdlsnip.instantiate").names())
  end,
  desc = "Instantiate an entity from the project; ! adds its signals",
})

vim.api.nvim_create_user_command("HdlSnipEdit", function()
  require("hdlsnip.form").edit(0)
end, { desc = "Edit the parameters of the template under the cursor" })

vim.api.nvim_create_user_command("HdlSnipLspAttach", function()
  require("hdlsnip.lsp").attach(0)
end, { desc = "Attach the hdlsnip completion server to this buffer" })

-- Attach on VHDL buffers unless the user turned it off. In plugin/ rather
-- than setup(), so completion works without any configuration at all.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "vhdl",
  group = vim.api.nvim_create_augroup("hdlsnip.lsp", { clear = true }),
  desc = "Attach the hdlsnip completion server",
  callback = function(ev)
    local ok, cfg = pcall(require("hdlsnip.config").get, ev.buf)
    if ok and cfg.lsp then
      require("hdlsnip.lsp").attach(ev.buf)
    end
  end,
})
