# main zsh settings. env in ~/.zprofile
# read second


# source global shell alias & variables files
# [ -f "$XDG_CONFIG_HOME/shell/alias" ] && source "$XDG_CONFIG_HOME/shell/alias"
# [ -f "$XDG_CONFIG_HOME/shell/vars" ] && source "$XDG_CONFIG_HOME/shell/vars"

# load modules
zmodload zsh/complist
autoload -U compinit && compinit
autoload -U colors && colors
# autoload -U tetris # main attraction of zsh, obviously


# cmp opts
zstyle ':completion:*' menu select # tab opens cmp menu
zstyle ':completion:*' special-dirs true # force . and .. to show in cmp menu
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS} ma=0\;33 # colorize cmp menu
# zstyle ':completion:*' file-list true # more detailed list
zstyle ':completion:*' squeeze-slashes false # explicit disable to allow /*/ expansion

# main opts
setopt append_history inc_append_history share_history # better history
# on exit, history appends rather than overwrites; history is appended as soon as cmds executed; history shared across sessions
setopt auto_menu menu_complete # autocmp first menu match
setopt autocd # type a dir to cd
setopt auto_param_slash # when a dir is completed, add a / instead of a trailing space
setopt no_case_glob no_case_match # make cmp case insensitive
setopt globdots # include dotfiles
setopt extended_glob # match ~ # ^
setopt interactive_comments # allow comments in shell
unsetopt prompt_sp # don't autoclean blanklines
stty stop undef # disable accidental ctrl s

# history opts
HISTSIZE=1000000
SAVEHIST=1000000
HISTFILE="$XDG_CACHE_HOME/zsh_history" # move histfile to cache
HISTCONTROL=ignoreboth # consecutive duplicates & commands starting with space are not saved


# fzf setup
#source <(fzf --zsh) # allow for fzf history widget
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -r /usr/share/fzf/completion.zsh   ]] && source /usr/share/fzf/completion.zsh
[[ -s "$HOME/.qfc/bin/qfc.sh" ]] && source "$HOME/.qfc/bin/qfc.sh"


# binds
bindkey -e
bindkey "^a" beginning-of-line
bindkey "^e" end-of-line
bindkey "^k" kill-line
bindkey "^j" backward-word
bindkey "^k" forward-word
bindkey "^H" backward-kill-word
# ctrl J & K for going up and down in prev commands
# bindkey "^J" history-search-forward
# bindkey "^K" history-search-backward
bindkey '^R' fzf-history-widget


function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  command yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd <"$tmp"
  [[ -n "$cwd" && "$cwd" != "$PWD" && -d "$cwd" ]] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}
alias yazi='y'
alias ls='eza --hyperlink --icons --color=always'
alias cat='bat --paging=never'
alias grep='grep --color=auto'
alias v='nvim' vi='nvim' vim='nvim'
alias kit-sl='bash $SCRIPTS_DIR/kit-sl.sh'
alias sudoedit='EDITOR=nvim sudoedit'
alias displayFilesFind="find . -type f -exec sh -c 'echo \"FILE: \$1\"; cat \"\$1\"; echo \"---\"' _ {} \;"


# open yazi with ctrl f (cd's into the folder you quit in)
openyazi() {
  y <$TTY
  local f; for f in $precmd_functions; do $f; done   # rebuild prompt (git segment)
  zle reset-prompt
}
zle -N openyazi
bindkey '^f' openyazi

(( $+commands[zoxide] )) && eval "$(zoxide init zsh --cmd cd)"

# set up prompt
NEWLINE=$'\n'

echo -e "${NEWLINE}\x1b[38;5;137m\x1b[48;5;0m it's$(print -P '%D{%_I:%M%P}\n') \x1b[38;5;180m\x1b[48;5;0m $(uptime -p | cut -c 4-) \x1b[38;5;223m\x1b[48;5;0m $(uname -r) \033[0m" # current

autoload -Uz vcs_info add-zsh-hook
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true   # runs git diff; slower in huge repos
zstyle ':vcs_info:git:*' stagedstr '+'
zstyle ':vcs_info:git:*' unstagedstr '!'
zstyle ':vcs_info:git:*' formats       '%b %u%c'
zstyle ':vcs_info:git:*' actionformats '%b|%a %u%c'

export VIRTUAL_ENV_DISABLE_PROMPT=1   # stop activate from editing PROMPT

_prompt_build() {
  local -i ec=$?
  vcs_info
  local L=$'\ue0b6' R=$'\ue0b0' BR=$'\ue0a0' PY=$'\ue73c'
  local last='#ffb3af'   # bg of previous segment, so arrows always match
  local p="%F{#ffb3af}$L%K{#ffb3af}%F{#571d1d} %(3~|…/%1~|%~) "

  if [[ -n $vcs_info_msg_0_ ]]; then
    p+="%K{#5d3f3d}%F{$last}$R%F{#ffdad7} $BR ${vcs_info_msg_0_% } "
    last='#5d3f3d'
  fi

  if [[ -n $VIRTUAL_ENV ]]; then
    p+="%K{#594319}%F{$last}$R%F{#ffdea8} $PY ${VIRTUAL_ENV:t} "
    last='#594319'
  fi

  p+="%k%F{$last}$R%f"
  local c='#ffb3af'; (( ec )) && c='#ffb4ab'
  PROMPT="$p"$'\n'"%B%F{$c}❯%f%b "
}
add-zsh-hook precmd _prompt_build













# autosuggestions
# requires zsh-autosuggestions
# source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# syntax highlighting
# requires zsh-syntax-highlighting package
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
