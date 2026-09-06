# The point of the whole plugin: one configuration change, and the same
# template emits a different reset structure.
#
#   vhs demo/config.tape

Output demo/config.gif
Output demo/config.txt

Require nvim

Set Shell "bash"
Set FontSize 16
Set Width 1100
Set Height 820
Set Padding 20
Set TypingSpeed 70ms
Set Theme "GruvboxDark"

Hide
Type "cd demo/project && clear" Enter
Type "stty -ixon" Enter
Type "nvim -u ../init.lua src/fifo.vhd" Enter
Sleep 2000ms
Show

Type "/begin"
Enter
Sleep 300ms
Escape
Sleep 600ms
Type "o"
Sleep 300ms
Enter
Sleep 300ms

# Asynchronous, active low: the reset branch sits outside the clock test.
Type "prc"
Sleep 800ms
Ctrl+S
Sleep 1200ms
Enter
Sleep 3000ms

Sleep 1000ms

# Switch the house style to a synchronous, active high reset.
Type ":lua require('hdlsnip').setup({ reset = { style = 'sync' } })"
Sleep 1500ms
Enter
Sleep 1000ms

# Past the end of the first process, still inside the architecture.
Type "/end process"
Enter
Sleep 600ms
Type "o"
Sleep 300ms
Enter
Sleep 300ms

# Same template, same trigger. The reset moves inside the clock test and
# leaves the sensitivity list.
Type "prc"
Sleep 800ms
Ctrl+S
Sleep 1200ms
Ctrl+U
Sleep 200ms
Type "wr_ptr"
Sleep 500ms
Enter
Sleep 4000ms

# Clear the message line and let the overlay fade, off camera, so the last
# frame is only the two processes.
Hide
Escape
Type ":"
Escape
Sleep 1500ms
Show
Sleep 3000ms
