# Reading entities that already exist and writing their instantiations.
#
#   vhs demo/instantiate.tape

Output demo/instantiate.gif
Output demo/instantiate.txt

Require nvim

Set Shell "bash"
Set FontSize 13
Set Width 1100
Set Height 900
Set Padding 20
Set TypingSpeed 75ms
Set Theme "GruvboxDark"

Hide
Type "rm -rf /tmp/hdlsnip-demo && mkdir -p /tmp/hdlsnip-demo/src" Enter
Type "cd /tmp/hdlsnip-demo && clear" Enter
Type "stty -ixon" Enter

# Fourteen designs, generated headlessly. Driving fourteen dialogs through
# the recorder was timing dependent and never twice the same.
Type "nvim --headless -u ~/dev/hdlsnip.nvim/demo/init.lua -c 'luafile ~/dev/hdlsnip.nvim/demo/fixtures.lua' -c 'qa!'" Enter
Sleep 4000ms
Type "clear" Enter

Type "nvim -u ~/dev/hdlsnip.nvim/demo/init.lua src/top.vhd" Enter
Sleep 2000ms
Type ":HdlSnip entity" Enter
Sleep 900ms
Enter
Sleep 900ms
Type "/begin" Enter
Type "j"
Sleep 1800ms
Show

Sleep 1200ms

# --- 1. Paging through more entities than fit ------------------------------
Type ":HdlSnipInstantiate!" Enter
Sleep 1800ms

Ctrl+D
Sleep 800ms
Ctrl+D
Sleep 1400ms

# --- 2. One at a time, then take a small one -------------------------------
Ctrl+K
Sleep 600ms
Ctrl+K
Sleep 400ms
Ctrl+K
Sleep 300ms
Ctrl+K
Sleep 300ms
Ctrl+K
Sleep 400ms
Ctrl+K
Sleep 700ms
Ctrl+J
Sleep 900ms
Enter
Sleep 2200ms

# --- 3. The FIFO, by filtering ---------------------------------------------
Type "G"
Type "k"
Sleep 500ms
Type ":HdlSnipInstantiate!" Enter
Sleep 1600ms

Type "fifo"
Sleep 1400ms
Ctrl+K
Sleep 800ms
Enter
Sleep 100ms

# Signals above begin, the instances below it, named association throughout.
Type "0"
Sleep 100ms
Ctrl+D
Sleep 2500ms

Hide
Escape
Type ":"
Escape
Sleep 1200ms
Show
Sleep 2500ms
