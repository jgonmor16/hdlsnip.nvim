# The completion menu: every template, from a server that is a Lua table.
#
#   vhs demo/menu.tape

Output demo/menu.gif
Output demo/menu.txt

Require nvim

Set Shell "bash"
Set FontSize 16
Set Width 1100
Set Height 620
Set Padding 20
Set TypingSpeed 70ms
Set Theme "GruvboxDark"

Hide
Type "cd demo/project && clear" Enter
Type "stty -ixon" Enter
Type "nvim -u ../init.lua src/menu.vhd" Enter
Sleep 2500ms
Show

Sleep 700ms
Type "i"
Sleep 300ms

# No keypress: the menu opens while typing. Seventeen templates, each
# saying whether it will ask for parameters.
Type "a"
Sleep 900ms
Type "x"
Sleep 2500ms

# A static template expands as a snippet.
Escape
Sleep 150ms
Type "cc"
Type "pk"
Sleep 1200ms
Ctrl+N
Sleep 600ms
Ctrl+Y
Sleep 1000ms
Type "axi_lite_pkg"
Sleep 2000ms

# Into the body, so the package has something in it.
Ctrl+K
Sleep 600ms
Type "constant C_DATA_WIDTH : positive := 32;"
Sleep 2000ms
Escape
Sleep 150ms

Hide
Type ":"
Escape
Sleep 1200ms
Show
Sleep 1200ms

