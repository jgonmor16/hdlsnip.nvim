# Changing your mind: the block re-renders as the dialog is edited.
#
#   vhs demo/live.tape

Output demo/live.gif
Output demo/live.txt

Require nvim

Set Shell "bash"
Set FontSize 15
Set Width 1100
Set Height 760
Set Padding 20
Set TypingSpeed 70ms
Set Theme "GruvboxDark"

Hide
Type "cd demo/project && clear" Enter
Type "stty -ixon" Enter
Type "nvim -u ../init.lua src/live.vhd" Enter
Sleep 2500ms
Show

Sleep 700ms

# A synchroniser, asked for once.
Type ":HdlSnip bit_sync" Enter
Sleep 1000ms
Ctrl+W
Type "flag_sync"
Sleep 600ms
Enter
Sleep 2500ms

# Now change its mind: the generic, the name, and the block follows.
Type "gg"
Sleep 300ms
Type "/G_STAGES" Enter
Sleep 800ms
Type ":HdlSnipEdit" Enter
Sleep 1200ms

Ctrl+K
Sleep 600ms
# A value the design cannot take: the dialog says so, and leaves the block
# alone until it is corrected.
Ctrl+W
Type "9"
Sleep 1500ms
Ctrl+W
Type "6"
Sleep 2200ms

Ctrl+J
Sleep 500ms
Ctrl+W
Type "cmd_sync"
Sleep 2500ms

Enter
Sleep 1000ms

Hide
Type ":"
Escape
Sleep 1200ms
Show
Sleep 2500ms
