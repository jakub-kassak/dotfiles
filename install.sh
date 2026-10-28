#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}"

info() { printf "\033[1;34m[dotfiles]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[   ok   ]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[  warn  ]\033[0m %s\n" "$*"; }

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --stow-only   Only symlink configuration files via GNU Stow (skip Homebrew packages)
  --brew-only   Only install Homebrew packages from Brewfile
  --help        Show this help message
EOF
}

STOW_ONLY=0
BREW_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --stow-only) STOW_ONLY=1 ;;
        --brew-only) BREW_ONLY=1 ;;
        --help|-h) usage; exit 0 ;;
        *) warn "Unknown option: $arg"; usage; exit 1 ;;
    esac
done

# 1. Install Homebrew & Bundle (macOS)
if [[ "$STOW_ONLY" -eq 0 ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
        if ! command -v brew >/dev/null 2>&1; then
            info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        info "Installing packages from Brewfile..."
        brew bundle --file="$DOTFILES_DIR/Brewfile" || warn "Some Brewfile items reported warnings; continuing..."
        ok "Homebrew packages installed."
    else
        warn "Non-macOS system detected; skipping macOS Brewfile bundle."
    fi
fi

if [[ "$BREW_ONLY" -eq 1 ]]; then
    exit 0
fi

# 2. Initialize Git Submodules (Oh My Zsh plugins & Powerlevel10k)
if [[ -f "$DOTFILES_DIR/.gitmodules" ]]; then
    info "Initializing git submodules..."
    git -C "$DOTFILES_DIR" submodule update --init --recursive
fi

# 3. Ensure base directories exist so Stow links inside them cleanly
mkdir -p \
    "$TARGET_DIR/.config" \
    "$TARGET_DIR/.local/bin" \
    "$TARGET_DIR/.oh-my-zsh" \
    "$TARGET_DIR/Library/Application Support/lazygit" \
    "$TARGET_DIR/Library/Application Support/sioyek"

# 4. Stow packages
STOW_PACKAGES=(
    aerospace
    borders
    btop
    espanso
    ghostty
    hammerspoon
    karabiner
    kvim
    lazygit
    linearmouse
    nnn
    nvim
    oh-my-zsh
    sioyek
    starship
    tmux
    wezterm
    zellij
    zsh
)

if ! command -v stow >/dev/null 2>&1; then
    warn "GNU Stow is not installed. Install it via 'brew install stow' first."
    exit 1
fi

BACKUP_ROOT="$TARGET_DIR/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

backup_if_real_path() {
    local rel="$1"
    local dst="$TARGET_DIR/$rel"
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        mkdir -p "$(dirname "$BACKUP_ROOT/$rel")"
        mv "$dst" "$BACKUP_ROOT/$rel"
        warn "Backed up existing $dst -> $BACKUP_ROOT/$rel"
    fi
}

# Back up common non-symlink conflicts on a fresh machine before stowing
if [[ -L "$TARGET_DIR/.config/zellij" && "$(readlink "$TARGET_DIR/.config/zellij")" == "$DOTFILES_DIR/zellij" ]]; then
    rm -f "$TARGET_DIR/.config/zellij"
fi
backup_if_real_path ".zshrc"
backup_if_real_path ".p10k.zsh"
backup_if_real_path ".tmux.conf"
backup_if_real_path ".hammerspoon"
backup_if_real_path ".config/aerospace"
backup_if_real_path ".config/borders"
backup_if_real_path ".config/btop"
backup_if_real_path ".config/ghostty"
backup_if_real_path ".config/karabiner"
backup_if_real_path ".config/kvim"
backup_if_real_path ".config/lazygit"
backup_if_real_path ".config/linearmouse"
backup_if_real_path ".config/nnn"
backup_if_real_path ".config/nvim"
backup_if_real_path ".config/starship"
backup_if_real_path ".config/wezterm"
backup_if_real_path ".config/zellij"
backup_if_real_path "Library/Application Support/espanso"
backup_if_real_path "Library/Application Support/lazygit/config.yml"
backup_if_real_path "Library/Application Support/sioyek/keys_user.config"
backup_if_real_path "Library/Application Support/sioyek/prefs_user.config"

info "Linking dotfiles into $TARGET_DIR via GNU Stow..."
for pkg in "${STOW_PACKAGES[@]}"; do
    if [[ -d "$DOTFILES_DIR/$pkg" ]]; then
        stow --restow -d "$DOTFILES_DIR" -t "$TARGET_DIR" "$pkg"
        ok "Stowed $pkg"
    fi
done

# 5. Create ~/.zsh_secrets template if missing
if [[ ! -f "$TARGET_DIR/.zsh_secrets" ]]; then
    cat > "$TARGET_DIR/.zsh_secrets" <<'EOF'
# Local API keys and secrets (never committed to git)
# export OPENAI_API_KEY="sk-..."
# export GEMINI_API_KEY="AIza..."
EOF
    chmod 600 "$TARGET_DIR/.zsh_secrets"
    info "Created template ~/.zsh_secrets (chmod 600)."
fi

# 6. Start JankyBorders & reload live services if running on macOS
if [[ "$(uname -s)" == "Darwin" ]]; then
    if command -v brew >/dev/null 2>&1 && brew list borders >/dev/null 2>&1; then
        brew services start borders >/dev/null 2>&1 || true
    fi
    if command -v aerospace >/dev/null 2>&1 && pgrep -x AeroSpace >/dev/null 2>&1; then
        aerospace reload-config >/dev/null 2>&1 || true
        ok "Reloaded AeroSpace config."
    fi
    if command -v hs >/dev/null 2>&1 && pgrep -x Hammerspoon >/dev/null 2>&1; then
        hs -c "hs.reload()" >/dev/null 2>&1 || true
        ok "Reloaded Hammerspoon config."
    fi
fi

ok "Setup complete! See README.md for macOS Accessibility permissions & API key notes."
