# Reading an entity and writing the testbench around it.
#
#   vhs demo/testbench.tape

Output demo/testbench.gif
Output demo/testbench.txt

Require nvim

Set Shell "bash"
Set FontSize 13
Set Width 1100
Set Height 900
Set Padding 20
Set TypingSpeed 75ms
Set Theme "GruvboxDark"

Hide
Type "rm -rf /tmp/hdlsnip-tb && mkdir -p /tmp/hdlsnip-tb/src" Enter
Type "cd /tmp/hdlsnip-tb && clear" Enter
Type "stty -ixon" Enter
Type "nvim --headless -u ~/dev/hdlsnip.nvim/demo/init.lua -c 'luafile ~/dev/hdlsnip.nvim/demo/testbench_fixture.lua' -c 'qa!'" Enter
Sleep 4000ms
Type "clear" Enter
Type "nvim -u ~/dev/hdlsnip.nvim/demo/init.lua src/top.vhd" Enter
Sleep 2500ms
Show

Sleep 1200ms

# Every design in the project, with its port count.
Type ":HdlSnipTestbench" Enter
Sleep 2000ms

# More than fit: page through, and wrap at the end.
Ctrl+D
Sleep 700ms
Ctrl+D
Sleep 1200ms

# One at a time.
Ctrl+K
Sleep 400ms
Ctrl+K
Sleep 300ms
Ctrl+K
Sleep 600ms
Ctrl+J
Sleep 1000ms

# Or type to narrow it.
Type "afifo"
Sleep 1800ms
Enter
Sleep 2500ms

# Signals for every port, the clock generated, the reset released, the DUT
# wired up and a stimulus process that stops the run.
Type "gg"
Sleep 2200ms
Ctrl+D
Sleep 2500ms

Hide
Escape
Type ":"
Escape
Sleep 1200ms
Show
Sleep 2500ms

