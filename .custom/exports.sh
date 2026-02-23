#!/usr/bin/env bash

export LANG=en_GB.UTF-8

export CARGOINSTALLPATH="$HOME/.cargo/bin/"
export PATH="$CARGOINSTALLPATH:$PATH"

export MASON_INSTALLED_LSPS="$HOME/.local/share/Simplexity.nvim/mason/bin/"
export PATH="$MASON_INSTALLED_LSPS:$PATH"

export PIPBIN="$HOME/.local/bin/"
export PATH="$PIPBIN:$PATH"

# Clean and deduplicate PATH
export PATH=$(echo "$PATH" | tr ':' '\n' | sed 's:/*$::' | awk '!x[$0]++' | paste -sd ':' -)

if [ -z "$SSH_AUTH_SOCK" ]; then
   eval "$(ssh-agent -s)" > /dev/null
fi

