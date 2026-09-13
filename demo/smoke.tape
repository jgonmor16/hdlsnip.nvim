# Interactive smoke check: every command and every interactive path, one
# frame per action, no waiting. Read demo/smoke.txt afterwards.
#
#   vhs demo/smoke.tape
#
# For the templates themselves see scripts/smoke.lua, which renders all of
# them under several configurations without a terminal.

Output demo/smoke.txt

Require nvim

Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 800
Set Padding 0
Set TypingSpeed 5ms

Hide
Type "cd demo/project && clear" Enter
Type "stty -ixon" Enter
Type "nvim -u ../init.lua src/smoke.vhd" Enter
Sleep 2s
Show

# --- health -----------------------------------------------------------------
Escape
Sleep 100ms
Type ":checkhealth hdlsnip" Enter
Sleep 800ms
Type ":q" Enter
Sleep 200ms

# --- the client is attached -------------------------------------------------
Escape
Sleep 100ms
Type ":lua =vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = 0 }))" Enter
Sleep 500ms

# --- command completion lists every template --------------------------------
Escape
Sleep 100ms
Type ":HdlSnip " Tab
Sleep 500ms
Escape
Sleep 200ms

# --- static template, prompted ----------------------------------------------
Escape
Sleep 100ms
Type ":HdlSnip package" Enter
Sleep 400ms
Ctrl+U
Type "smoke_pkg" Enter
Sleep 500ms

# --- static template as a snippet, with a tabstop ---------------------------
Escape
Sleep 100ms
Type "G" Type "o"
Sleep 200ms
Ctrl+K
Sleep 200ms
Escape
Sleep 100ms
Type ":HdlSnipExpand package" Enter
Sleep 500ms
Type "snippet_pkg"
Sleep 300ms
Escape
Sleep 200ms

# --- trigger expansion in insert mode ---------------------------------------
Escape
Sleep 100ms
Type "Go"
Type "prc"
Ctrl+K
Sleep 400ms
Ctrl+U
Type "trigger" Enter
Sleep 500ms

# --- completion menu, from the in-process LSP server ------------------------
Escape
Sleep 100ms
Type "Go"
Type "pk"
Sleep 900ms
Ctrl+N
Sleep 300ms
Ctrl+Y
Sleep 400ms
Type "from_completion"
Sleep 300ms
Escape
Sleep 200ms

# --- dynamic template, prompted ---------------------------------------------
Escape
Sleep 100ms
Type ":HdlSnip bit_sync" Enter
Sleep 400ms
Ctrl+U
Type "smoke_sync" Enter
Sleep 300ms
Ctrl+U
Type "3" Enter
Sleep 600ms

# --- mixed template: declarations above begin, statements below -------------
Escape
Sleep 100ms
Type ":HdlSnip entity" Enter
Sleep 300ms
Ctrl+U
Type "smoke_top" Enter
Sleep 200ms
Ctrl+U
Type "rtl" Enter
Sleep 200ms
Enter
Sleep 500ms
Type "/begin" Enter
Type "j"
Type ":HdlSnip fsm" Enter
Sleep 300ms
Ctrl+U
Type "smoke" Enter
Sleep 200ms
Ctrl+U
Type "idle, run, done" Enter
Sleep 700ms

# --- live editing of a tracked block ----------------------------------------
Escape
Sleep 100ms
Type "?p_trigger" Enter
Sleep 300ms
Type ":HdlSnipEdit" Enter
Sleep 500ms
Type "A"
Ctrl+U
Type "renamed"
Sleep 700ms
Enter
Sleep 600ms

# --- configuration changes the shape ----------------------------------------
Escape
Sleep 100ms
Type ":lua require('hdlsnip').setup({ keyword_case = 'upper', reset = { style = 'sync' } })" Enter
Sleep 300ms
Type "Go"
Type "prc"
Ctrl+K
Sleep 300ms
Ctrl+U
Type "after_config" Enter
Sleep 600ms

# --- rescan, and an error path ----------------------------------------------
Escape
Sleep 100ms
Type ":HdlSnipReload" Enter
Sleep 500ms
Type ":HdlSnip no_such_template" Enter
Sleep 500ms
Type ":HdlSnip package" Enter
Sleep 300ms
Ctrl+U
Type "entity" Enter
Sleep 700ms

# --- the whole buffer -------------------------------------------------------
Escape
Sleep 100ms
Type ":%p" Enter
Sleep 1s

