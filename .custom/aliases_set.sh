#!/usr/bin/env bash

#nvims
alias cvim="NVIM_APPNAME=Complexity.nvim nvim"
alias xvim="NVIM_APPNAME=Simplexity.nvim nvim"
alias svim="NVIM_APPNAME=Simplicity.nvim nvim"
alias tvim="NVIM_APPNAME=Tiny.nvim nvim"

#systems
alias rebt="systemctl reboot"
alias shut="systemctl poweroff"
alias hiber="systemctl hibernate"

# other
alias la="ls -Af --color=auto"
alias ls='ls --color=auto'
alias l='ls -CF'

# colour
alias grep='grep --color=auto'

alias c="clear"
alias f="fastfetch"
alias e="exit"
alias b="btop"
alias a="cava"

# cd
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."

# Always set rmf to the standard rm command
alias rmf="/usr/bin/rm"

# If trash exists we make rm trash, else we make it interactive
if command -v trash >/dev/null 2>&1; then
    alias rm="trash"
else
    alias rm="rm -i"
fi
