# Completion: templates in the menu, from an in-process LSP server.
#
#   vhs demo/completion.tape

Output demo/completion.gif
Output demo/completion.txt

Require nvim

Set Shell "bash"
Set FontSize 16
Set Width 1100
Set Height 660
Set Padding 20
Set TypingSpeed 70ms
Set Theme "GruvboxDark"

Hide
Type "cd demo/project && clear" Enter
Type "stty -ixon" Enter
Type "nvim -u ../init.lua src/pkg.vhd" Enter
Sleep 2500ms
Show

Sleep 600ms
Type "i"
Sleep 400ms

# The menu appears while typing: no keypress, no completion plugin.
Type "p"
Sleep 700ms
Type "k"
Sleep 1500ms

# Accept, and the snippet expands with the name as the first tabstop.
Ctrl+N
Sleep 800ms
Ctrl+Y
Sleep 1500ms

Type "axi_lite_pkg"
Sleep 1500ms

# The same key that expands a trigger also moves to the next tabstop.
Ctrl+K
Sleep 900ms
Type "constant C_ADDR_WIDTH : positive := 32;"
Sleep 2000ms

Hide
Escape
Type ":"
Escape
Sleep 1500ms
Show
Sleep 2500ms
