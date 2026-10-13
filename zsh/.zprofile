export EDITOR="nvim"
export VISUAL="nvim"

export BROWSER="zen-browser"
export XDG_BROWSER="zen-browser"

export TERMINAL="kitty"
export FILE_MANAGER="thunar"
# export MUSIC_PLAYER="mpd"
export VIDEO_PLAYER="vlc"
export IMAGE_VIEWER="imv"
#export DOCUMENT_VIEWER=""
export TEXT_EDITOR="nvim"
export PDF_VIEWER="zen-browser"

# Variables for custom scripts
export SCRIPTS_DIR="$HOME/Documents/Scripts"

typeset -U path
path=(~/.local/bin(N/) ~/.cargo/bin(N/) $path)

export FZF_DEFAULT_OPTS="--style minimal --color 16 --layout=reverse --height 30% --preview='bat -p --color=always {}'"
export FZF_CTRL_R_OPTS="--style minimal --color 16 --info inline --no-sort --no-preview"
export MANPAGER="less -R --use-color -Dd+r -Du+b"

export LESS="R --use-color -Dd+r -Du+b"
export LESS_TERMCAP_mb="$(printf '%b' '[1;31m')"
export LESS_TERMCAP_md="$(printf '%b' '[1;36m')"
export LESS_TERMCAP_me="$(printf '%b' '[0m')"
export LESS_TERMCAP_so="$(printf '%b' '[01;44;33m')"
export LESS_TERMCAP_se="$(printf '%b' '[0m')"
export LESS_TERMCAP_us="$(printf '%b' '[1;32m')"
export LESS_TERMCAP_ue="$(printf '%b' '[0m')"

# MPD daemon start (if no other user instance exists)
[[ ! -s ~/.config/mpd/pid ]] && mpd
