
#!/usr/bin/env zsh

ZINIT_HOME="$HOME/.zinit"
if [[ ! -d $ZINIT_HOME ]]; then
    echo "Installing Zinit..."
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com "$ZINIT_HOME"
fi
source "$ZINIT_HOME/zinit.zsh"

# 1. Load Theme (Instant Prompt safe)
zinit light romkatv/powerlevel10k

# 2. Base Completion Engine System Configuration
zinit wait lucid for \
    atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" \
    blockf \
    zsh-users/zsh-completions

# 3. Handle Oh My Zsh Library & Snippets Asynchronously
zinit ice wait lucid
zinit light ohmyzsh/ohmyzsh

zinit ice wait lucid; zinit snippet OMZP::colored-man-pages
zinit ice wait lucid; zinit snippet OMZP::cp
zinit ice wait lucid; zinit snippet OMZP::copyfile
zinit ice wait lucid; zinit snippet OMZP::archlinux

# 4. Optional Tooling Initialization
if command -v zoxide >/dev/null 2>&1; then
    export _ZO_MAXAGE=100
    eval "$(zoxide init zsh)"

    zinit ice wait lucid
    zinit snippet OMZP::zoxide

    alias cd='z'
fi

# 5. UI Elements: Load Autosuggestions with pre-compilation for instant redraw bounds
zinit ice wait lucid atclone"zedit -i d"
zinit light zsh-users/zsh-autosuggestions

# 6. Syntax Highlighting (CRITICAL: Must load dead last to avoid cursor shifting)
zinit ice wait lucid atload"zicdreplay"
zinit light zsh-users/zsh-syntax-highlighting

# History & Key Bindings Configuration
HISTFILE="$IMPORTS/.zhistory"
SAVEHIST=500
HISTSIZE=500
setopt share_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_verify
setopt COMBINING_CHARS
setopt INTERACTIVE_COMMENTS
