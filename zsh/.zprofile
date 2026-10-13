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

# MPD daemon start (if no other user instance exists)
[[ ! -s ~/.config/mpd/pid ]] && mpd
