#!/bin/sh
# Canonical PolyLinux high-contrast palette for the black v86 terminal.
# Keep this file byte-identical in every lab repository that packages it.
POLYLINUX_LS_COLORS='no=0:fi=0;97:di=1;96:ln=1;95:pi=1;93:so=1;93:bd=1;93:cd=1;93:or=97;41:mi=97;41:ex=1;92:*.tar=1;91:*.tgz=1;91:*.arc=1;91:*.arj=1;91:*.taz=1;91:*.lha=1;91:*.lz4=1;91:*.lzh=1;91:*.lzma=1;91:*.tlz=1;91:*.txz=1;91:*.tzo=1;91:*.t7z=1;91:*.zip=1;91:*.z=1;91:*.dz=1;91:*.gz=1;91:*.lrz=1;91:*.lz=1;91:*.lzo=1;91:*.xz=1;91:*.zst=1;91:*.tzst=1;91:*.bz2=1;91:*.bz=1;91:*.tbz=1;91:*.tbz2=1;91:*.tz=1;91:*.deb=1;91:*.rpm=1;91:*.jar=1;91:*.war=1;91:*.ear=1;91:*.sar=1;91:*.rar=1;91:*.alz=1;91:*.ace=1;91:*.zoo=1;91:*.cpio=1;91:*.7z=1;91:*.rz=1;91:*.cab=1;91:*.wim=1;91:*.swm=1;91:*.dwm=1;91:*.esd=1;91'
LS_COLORS=$POLYLINUX_LS_COLORS
export POLYLINUX_LS_COLORS LS_COLORS

# GNU ls defaults to no color. "auto" preserves clean redirected/piped output.
alias ls='ls --color=auto'
