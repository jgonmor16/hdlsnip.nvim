# Snippet path: a static template with tabstops and mirroring.
#
#   vhs demo/snippet.tape

Output demo/snippet.gif
Output demo/snippet.txt

Require nvim

Set Shell "bash"
Set FontSize 18
Set Width 1100
Set Height 680
Set Padding 20
Set TypingSpeed 70ms
Set Theme "GruvboxDark"

Hide
Type "cd demo/project && clear" Enter
Type "stty -ixon" Enter
Type "nvim -u ../init.lua src/pkg.vhd" Enter
Sleep 2000ms
Show

Sleep 300ms
Type "i"
Sleep 400ms

Type "pkg"
Sleep 900ms
Ctrl+S
Sleep 1200ms

Type "axi_lite_pkg"
Sleep 1500ms

Ctrl+L
Sleep 800ms
Type "constant C_ADDR_WIDTH : positive := 32;"
Sleep 2000ms

Escape
Sleep 2500ms
