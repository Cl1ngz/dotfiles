#!/usr/bin/env bash
# Bootstrap system dependencies for the nvim config.
# Portable across Arch / Debian+Ubuntu / Fedora / macOS.
#
#   ./bootstrap.sh
#
# Safe to re-run -- every step is idempotent. Everything else (LSP servers,
# formatters, linters) is handled by Mason inside Neovim.

set -euo pipefail

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$1"; }

# --- detect package manager -------------------------------------------------

if command -v pacman >/dev/null 2>&1; then
  PM=pacman
elif command -v apt >/dev/null 2>&1; then
  PM=apt
elif command -v dnf >/dev/null 2>&1; then
  PM=dnf
elif command -v brew >/dev/null 2>&1; then
  PM=brew
else
  warn "No supported package manager found (pacman/apt/dnf/brew)."
  warn "Install the deps listed in this script by hand, then re-run."
  exit 1
fi

info "Using $PM"

# --- system packages --------------------------------------------------------
# Same logical set everywhere, different names per distro.

case "$PM" in
  pacman)
    sudo pacman -S --needed --noconfirm \
      base-devel unzip curl git \
      nodejs-lts-jod npm \
      python python-pip \
      ripgrep fd \
      cppcheck \
      lazygit \
      tree-sitter-cli \
      qt6-declarative
    ;;

  apt)
    sudo apt update
    sudo apt install -y \
      build-essential unzip curl git \
      nodejs npm \
      python3 python3-pip python3-venv \
      ripgrep fd-find \
      cppcheck \
      qt6-declarative-dev
    warn "Debian/Ubuntu notes:"
    warn "  * fd is installed as 'fdfind'. Symlink it:"
    warn "      ln -s \$(which fdfind) ~/.local/bin/fd"
    warn "  * nodejs from apt is often ancient. Prefer nvm or nodesource."
    warn "  * lazygit is not in most apt repos -- install from its releases page."
    ;;

  dnf)
    sudo dnf install -y \
      @development-tools unzip curl git \
      nodejs npm \
      python3 python3-pip \
      ripgrep fd-find \
      cppcheck \
      lazygit \
      tree-sitter-cli \
      qt6-qtdeclarative-devel
    ;;

  brew)
    if ! xcode-select -p >/dev/null 2>&1; then
      info "Installing Xcode Command Line Tools"
      xcode-select --install || true
    fi
    brew install \
      node python ripgrep fd cppcheck lazygit qt
    warn "macOS note: qmlls/qmlformat live inside the qt keg, e.g."
    warn "  \$(brew --prefix qt)/bin/qmlls -- adjust lspconfig.lua if needed."
    ;;
esac

# --- tree-sitter CLI --------------------------------------------------------
# HARD requirement of nvim-treesitter's main branch: it shells out to this
# binary to compile parsers. Needs >= 0.26.1.
#
# Arch and Fedora package it (handled above). Elsewhere we fall back to npm --
# installed under $HOME, never with sudo. `npm install -g` defaults to
# /usr/lib/node_modules, which needs root and, on distros like Arch, is owned
# by the system package manager. Dropping unmanaged files there is a bad idea.

TS_MIN=0.26.1

# true when $1 >= $2
version_ge() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; }

# `|| true` matters: under `set -euo pipefail` a grep that matches nothing
# returns non-zero, which would abort the script instead of falling through
# to the npm install below.
ts_version() { tree-sitter --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true; }

install_ts_via_npm() {
  local prefix="$HOME/.local"
  info "Installing tree-sitter CLI via npm into $prefix"
  npm install -g --prefix "$prefix" tree-sitter-cli

  if ! command -v tree-sitter >/dev/null 2>&1; then
    warn "$prefix/bin is not on your PATH. Add this to your shell rc:"
    warn "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

if command -v tree-sitter >/dev/null 2>&1; then
  CURRENT="$(ts_version)"
  if [ -n "$CURRENT" ] && version_ge "$CURRENT" "$TS_MIN"; then
    info "tree-sitter CLI $CURRENT (>= $TS_MIN) -- ok"
  else
    warn "tree-sitter CLI ${CURRENT:-unknown} is older than $TS_MIN."
    warn "nvim-treesitter's main branch needs $TS_MIN or newer."
    install_ts_via_npm
  fi
else
  install_ts_via_npm
fi

# --- rust toolchain (optional) ----------------------------------------------
# rustaceanvim needs rust-analyzer; rustup ships it on every platform.

if command -v rustup >/dev/null 2>&1; then
  info "Ensuring rust-analyzer component"
  rustup component add rust-analyzer || true
else
  warn "rustup not found -- skipping rust-analyzer."
  warn "  Install from https://rustup.rs if you write Rust."
fi

# --- done -------------------------------------------------------------------

info "System deps ready."
info "Now launch nvim: lazy.nvim installs plugins, Mason installs LSP tooling."
info "Then run :checkhealth"
