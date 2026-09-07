-- Neovim configuration used only for recording the demo GIFs.
--
-- Isolated on purpose: no plugin manager, no user config, no colourscheme
-- from elsewhere. Two people running `make demo` should get the same frames.
local here = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(here, ":p:h:h")

vim.opt.runtimepath:prepend(root)

vim.opt.termguicolors = true
vim.opt.background = "dark"
vim.opt.number = true
vim.opt.signcolumn = "no"
vim.opt.laststatus = 0
vim.opt.ruler = false
vim.opt.showmode = false
vim.opt.showcmd = false
vim.opt.report = 9999
vim.opt.shortmess:append("I")
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.swapfile = false
vim.opt.hlsearch = false
vim.cmd.colorscheme("retrobox")

require("hdlsnip").setup({
  vhdl_std = "2008",
  reset = { style = "async", polarity = "low" },
  keys = {
    expand = "<C-k>",
    jump_prev = "<C-j>",
  },
})

-- Automatic completion from the built-in menu. `vim.lsp.completion.enable`
-- needs a client id, so it runs when the client attaches rather than at
-- startup. Neovim 0.11+.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, ev.data.client_id, ev.buf, {
        autotrigger = true,
      })
    end
  end,
})

-- Do not select an entry automatically, so the menu is readable on a
-- recording and <C-n> visibly moves.
vim.opt.completeopt = { "menuone", "noselect", "popup" }

-- ---------------------------------------------------------------------------
-- Keystroke overlay
-- ---------------------------------------------------------------------------
--
-- VHS renders headlessly through ttyd, so nothing outside Neovim can observe
-- the keys. This watches them from the inside with vim.on_key and draws the
-- last few in a floating window, which is enough to make a GIF followable.
--
-- Recording only. It has no place in the plugin itself.
local keycast = {
  keys = {},
  win = nil,
  buf = vim.api.nvim_create_buf(false, true),
  timer = assert(vim.uv.new_timer()),
}

local KEYCAST_MAX = 5 -- keys kept on screen
local KEYCAST_CLEAR = 1200 -- ms of idle before the overlay disappears
local KEYCAST_JOIN = 400 -- ms within which printable keys form one token

-- The overlay gets its own highlight rather than borrowing Visual or
-- PmenuSel, whose colours change with the colourscheme and can end up
-- louder than the code they sit next to.
vim.api.nvim_set_hl(0, "HdlsnipKeycast", {
  bg = "#3c3836",
  fg = "#ebdbb2",
  bold = true,
})

local function keycast_hide()
  if keycast.win and vim.api.nvim_win_is_valid(keycast.win) then
    vim.api.nvim_win_close(keycast.win, true)
  end
  keycast.win = nil
end

local function keycast_show()
  if #keycast.keys == 0 then
    return keycast_hide()
  end

  local text = " " .. table.concat(keycast.keys, " ") .. " "
  vim.api.nvim_buf_set_lines(keycast.buf, 0, -1, false, { text })

  local opts = {
    relative = "editor",
    anchor = "SE",
    row = vim.o.lines - 1,
    col = vim.o.columns - 2,
    width = vim.fn.strdisplaywidth(text),
    height = 1,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
    zindex = 200,
  }

  if keycast.win and vim.api.nvim_win_is_valid(keycast.win) then
    vim.api.nvim_win_set_config(keycast.win, opts)
  else
    keycast.win = vim.api.nvim_open_win(keycast.buf, false, opts)
    vim.wo[keycast.win].winhighlight =
      "Normal:HdlsnipKeycast,FloatBorder:HdlsnipKeycast"
  end
end

vim.on_key(function(_, typed)
  -- `typed` is what was actually pressed; the first argument is the result
  -- after mappings, which would show the expansion rather than the keystroke.
  if typed == nil or typed == "" then
    return
  end

  local key = vim.fn.keytrans(typed)
  local lowered = key:lower()
  if key == "" or lowered:match("mouse") or lowered:match("scrollwheel") then
    return
  end
  -- Collapse a run of printable characters into one entry: individual
  -- letters crowd out the key combinations, which are what a viewer is
  -- actually meant to see.
  local printable = vim.fn.strchars(key) == 1
  local last = keycast.keys[#keycast.keys]
  -- Group by rhythm rather than by mode: a burst of typing becomes one
  -- token, and a deliberate pause starts a new one. Mode events arrive a
  -- keystroke late when a snippet drops into select mode, which split words
  -- in the middle.
  local now = vim.uv.now()
  local joinable = printable
    and last
    and not last:match("^<")
    and (now - (keycast.last_at or 0)) < KEYCAST_JOIN
    and #last < 24
  keycast.last_at = now
  if joinable then
    keycast.keys[#keycast.keys] = last .. key
  else
    keycast.keys[#keycast.keys + 1] = key
  end
  while #keycast.keys > KEYCAST_MAX do
    table.remove(keycast.keys, 1)
  end

  vim.schedule(keycast_show)

  keycast.timer:stop()
  keycast.timer:start(
    KEYCAST_CLEAR,
    0,
    vim.schedule_wrap(function()
      keycast.keys = {}
      keycast_hide()
    end)
  )
end)
