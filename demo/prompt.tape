# Prompt path: a dynamic template, where the output depends on configuration
# rather than on a tabstop.
#
#   vhs demo/prompt.tape

Output demo/prompt.gif
Output demo/prompt.txt

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
Type "nvim -u ../init.lua src/cdc.vhd" Enter
Sleep 2000ms
Show

Sleep 500ms

Type ":HdlSnip bit_sync"
Sleep 700ms
Enter
Sleep 1200ms

# Entity name.
Ctrl+U
Sleep 300ms
Type "flag_sync"
Sleep 600ms
Enter
Sleep 1000ms

# Stage count, checked against the template's bounds.
Ctrl+U
Sleep 300ms
Type "3"
Sleep 600ms
Enter
Sleep 1500ms

# Clear the message line and let the overlay fade, off camera, so the last
# frame is only the two processes.
Hide
Escape
Type ":"
Escape
Sleep 1500ms
Show
Sleep 3000ms
