# Four keystrokes, two answers, and an AXI4-Lite slave that GHDL analyses and
# a testbench passes.
#
#   vhs demo/axil.tape

Output demo/axil.gif
Output demo/axil.txt

Require nvim

Set Shell "bash"
Set FontSize 13
Set Width 1100
Set Height 900
Set Padding 20
Set TypingSpeed 70ms
Set Theme "GruvboxDark"

Hide
Type "cd demo/project && clear" Enter
Type "stty -ixon" Enter
Type "nvim -u ../init.lua src/regs.vhd" Enter
Sleep 2500ms
Show

Sleep 800ms
Type "i"
Sleep 300ms

# Four characters.
Type "axil"
Sleep 900ms
Ctrl+K
Sleep 1400ms

# Two answers: what to call it, and how many registers.
Ctrl+W
Type "ctrl_regs"
Sleep 700ms
Ctrl+K
Sleep 400ms
Ctrl+W
Type "8"
Sleep 900ms
Enter
Sleep 2500ms

# The handshake, the byte strobes, the error response: all of it.
Type "gg"
Sleep 1500ms
Ctrl+D
Sleep 1800ms
Ctrl+D
Sleep 1800ms
Ctrl+D
Sleep 2000ms

Hide
Type ":"
Escape
Sleep 1200ms
Show
Sleep 2000ms
