#!/usr/bin/env bash
# ~/.bashrc
#
# If not running interactively, don't do anything
[[ $- != *i* ]] && return

PS1='[\u@\h \W]\$ '

eval "$(starship init bash)"

source /usr/share/fzf/key-bindings.bash
source /usr/share/fzf/completion.bash

[[ -s "$HOME/.qfc/bin/qfc.sh" ]] && source "$HOME/.qfc/bin/qfc.sh"

# Alliases
# i'm not longer using ls eza feels better
alias ls='eza --hyperlink --icons --color=always'

# bat is nice
alias cat='bat --paging=never'
alias grep='grep --color=auto'
alias date='date "+%d-%m-%Y %H:%M:%S"'

# Nvim aliases
alias v='nvim'
alias vi='nvim'
alias vim='nvim'

# Scripts
alias kit-sl='bash $SCRIPTS_DIR/kit-sl.sh'

# Start ssh-agent quietly and add my ed25519 key (if not already running).
# if [ -z "$SSH_AUTH_SOCK" ]; then
#   eval "$(keychain --quiet ~/.ssh/id_ed25519)"
# fi
#
#
# Yazzi
alias yazi='y'

# Yazzli wraper
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  command yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd <"$tmp"
  [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

# Zoxide
alias cd='z'
eval "$(zoxide init bash)"
. "$HOME/.cargo/env"

alias displayFilesFind="find . -type f -exec sh -c 'echo \"FILE: \$1\"; cat \"\$1\"; echo \"---\"' _ {} \;"

# Add local bin to PATH
if [ -d "$HOME/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
fi

alias sudoedit='EDITOR=nvim sudoedit'
