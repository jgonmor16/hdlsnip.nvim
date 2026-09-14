# Reading an entity and writing the testbench around it.
#
#   vhs demo/testbench.tape

Output demo/testbench.gif
Output demo/testbench.txt

Require nvim

Set Shell "bash"
Set FontSize 14
Set Width 1100
Set Height 860
Set Padding 20
Set TypingSpeed 75ms
Set Theme "GruvboxDark"

Hide
Type "rm -rf /tmp/hdlsnip-tb && mkdir -p /tmp/hdlsnip-tb/src" Enter
Type "cd /tmp/hdlsnip-tb && clear" Enter
Type "stty -ixon" Enter
Type "nvim --headless -u ~/dev/hdlsnip.nvim/demo/init.lua -c 'luafile ~/dev/hdlsnip.nvim/demo/testbench_fixture.lua' -c 'qa!'" Enter
Sleep 2500ms
Type "clear" Enter
Type "nvim -u ~/dev/hdlsnip.nvim/demo/init.lua src/fifo.vhd" Enter
Sleep 2000ms
Show

Sleep 1500ms

# A design with eight ports and two generics, already written.
Type ":HdlSnipTestbench" Enter
Sleep 1800ms
Enter
Sleep 1200ms

# Signals, clock, reset, the DUT wired up, and a stimulus process.
Type "gg"
Sleep 1800ms
Ctrl+D
Sleep 2500ms

Hide
Escape
Type ":"
Escape
Sleep 1200ms
Show
Sleep 2500ms
