# Ghostty shell integration
if [ -n "${GHOSTTY_RESOURCES_DIR}" ] && [ -f "${GHOSTTY_RESOURCES_DIR}/shell-integration/bash/ghostty.bash" ]; then
    source "${GHOSTTY_RESOURCES_DIR}/shell-integration/bash/ghostty.bash"
fi

# ============================================================
# Personal shell tools
# ============================================================

source "$HOME/.shell-tools"


# ============================================================
# Starship prompt
# ============================================================

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi


# ============================================================
# GNU ls
# ============================================================

if command -v gls >/dev/null 2>&1; then
    alias ls='gls --color=auto'
fi

export LS_COLORS='di=01;34:fi=00:ln=36:pi=33:so=35:bd=40;33:cd=40;33:or=31;01:ex=01;32'


# ============================================================
# Terminal
# ============================================================

export TERM="xterm-256color"


# ============================================================
# OrbStack
# ============================================================

if [ -f "$HOME/.orbstack/shell/init.bash" ]; then
    source "$HOME/.orbstack/shell/init.bash" 2>/dev/null || :
fi

# Load interactive bash configuration
[[ -f ~/.bashrc ]] && source ~/.bashrc
