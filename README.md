# macOS & Dev Environment Dotfiles (`jakub-kassak/dotfiles`)

Portable configuration and bootstrap script for quickly setting up or syncing a macOS machine using **Homebrew** and **GNU Stow**.

---

## Quick Start on a New Mac

```bash
# 1. Clone the repository (matching the existing path convention)
mkdir -p ~/02_UnsyncedFiles
git clone --recurse-submodules git@github.com:jakub-kassak/dotfiles.git ~/02_UnsyncedFiles/dotfiles

# 2. Run the full installer (installs Homebrew packages + symlinks all configs)
cd ~/02_UnsyncedFiles/dotfiles
./install.sh
```

To only refresh symlinks without running Homebrew:

```bash
./install.sh --stow-only
```

---

## Tracked Apps, Tools & Configurations

### 1. Window Management, Keyboard & Automation

| App / Tool | Install (`Brewfile`) | Dotfiles Package | Symlink Target | Purpose & Keybindings |
| :--- | :--- | :--- | :--- | :--- |
| **Hammerspoon** | `cask "hammerspoon"` | `hammerspoon/` | `~/.hammerspoon` | Hosts the **Writing Assistant (`Cmd+G`)**, **AeroSpace Workspace Switcher (`Ctrl+Opt+Cmd+Tab`)**, and **Title Case converter (`CapsLock+T` / `F19`)**. |
| **Writing / Grammar Assistant** | *(Inside Hammerspoon)* | `hammerspoon/.hammerspoon/grammar_checker.*` | `~/.hammerspoon/grammar_checker.*` | `Cmd+G` checks selected text or clipboard (`Correct`, `Polish`, `Concise`, `Formal`, EN/DE/SK translation, Lexicon, inline diff, guarded `Tab` replace). Uses OpenAI `gpt-6.1-sol` (via `~/.zsh_secrets` or OpenCode DB) and Gemini `gemini-3.7-flash`. |
| **AeroSpace** | `cask "nikitabobko/tap/aerospace"` | `aerospace/` | `~/.config/aerospace` | Tiling window manager (`cmd-ctrl-alt-h/j/k/l` directional focus, workspaces `1–9`, floating rules for Hammerspoon/Finder). |
| **JankyBorders** | `brew "felixkratz/formulae/borders"` | `borders/` | `~/.config/borders` | Draws a `4px` rounded border (`#00ff00` active, `#414550` inactive) around standard windows (`brew services start borders`). |
| **Karabiner-Elements** | `cask "karabiner-elements"` | `karabiner/` | `~/.config/karabiner` | Hyper/Space/CapsLock layers (`CapsLock` -> `Esc` / navigation layer, `Right Cmd` / held `Space` -> `Ctrl+Opt+Cmd`, `CapsLock+T` -> `F19` title case, `CapsLock+V` -> Maccy). |
| **Espanso** | `cask "espanso"` | `espanso/` | `~/Library/Application Support/espanso` | Text expander for LaTeX/math (`math.yml`), Lean (`;langle `, `;rangle ` in `lean.yml`), emojis (`emoji.yml`), and dates (`datetime.yml`). |
| **LinearMouse** | `cask "linearmouse"` | `linearmouse/` | `~/.config/linearmouse` | Per-device mouse scrolling direction & acceleration (`linearmouse.json`). |
| **Homerow** | `cask "homerow"` | *(macOS `defaults`)* | — | Keyboard label navigation (`Ctrl+Opt+Cmd+\` search, `Ctrl+Opt+Cmd+/` non-search, `Ctrl+Opt+Cmd+;` scroll). |
| **Shortcat** | `cask "shortcat"` | *(macOS `defaults`)* | — | UI element keyboard search (`Ctrl+Opt+Cmd+.`). |
| **Maccy** | `cask "maccy"` | *(macOS `defaults`)* | — | Lightweight clipboard history manager (triggered via `CapsLock+V`). |
| **Scroll Reverser / KeepingYouAwake / Bluesnooze** | `cask` | — | — | Menu bar utilities for trackpad/mouse scroll, sleep prevention, and Bluetooth audio disconnect on sleep. |

### 2. Terminals, Shell & Multiplexers

| App / Tool | Install (`Brewfile`) | Dotfiles Package | Symlink Target | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **WezTerm** | `cask "wezterm"` | `wezterm/` | `~/.config/wezterm` | Primary terminal with Solarized Light/Dark toggle (`Cmd+D`), Zellij passthrough keys, and `Ctrl+Click` / `Ctrl+Shift+O` open-in-Neovim RPC (`nvim_open.lua`). |
| **Ghostty** | `cask "ghostty"` | `ghostty/` | `~/.config/ghostty` | Fast native macOS terminal with matching Solarized themes and Zellij keybindings. |
| **Zsh + Oh My Zsh + Powerlevel10k** | Built-in + submodules | `zsh/`, `oh-my-zsh/` | `~/.zshrc`, `~/.p10k.zsh`, `~/.oh-my-zsh/custom` | Shell config, `auto_activate_venv`, `.env` loader, `nnn` cd-on-exit (`n`), cross-env clipboard (`cb`), and `zsh-autosuggestions` / `zsh-syntax-highlighting`. |
| **Zellij** | `brew "zellij"` | `zellij/` | `~/.config/zellij` | Terminal workspace multiplexer. |
| **Tmux** | `brew "tmux"` | `tmux/` | `~/.tmux.conf` | Fallback terminal multiplexer config. |
| **Starship** | `brew "starship"` | `starship/` | `~/.config/starship` | Cross-shell prompt config. |

### 3. Editors, Git, CLI & Academic Tools

| App / Tool | Install (`Brewfile`) | Dotfiles Package | Symlink Target | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Neovim (`nvim` & `kvim`)** | `brew "neovim"` | `nvim/`, `kvim/` | `~/.config/nvim`, `~/.config/kvim`, `~/.local/bin/kvim` | Full Neovim setup with LSP (`pyright`, `ruff`, `texlab`, `tinymist`, `lean.nvim`), auto-following macOS Light/Dark mode. |
| **Lazygit** | `brew "lazygit"` | `lazygit/` | `~/.config/lazygit` & `~/Library/Application Support/lazygit/config.yml` | Terminal Git UI with `delta` and `difftastic` (`lg` light / `lgd` dark). |
| **nnn** | `brew "nnn"` | `nnn/` | `~/.config/nnn` | Terminal file manager with bookmarks andplugins. |
| **btop** | `brew "btop"` | `btop/` | `~/.config/btop` | Resource monitor. |
| **Sioyek** | `/Applications/sioyek.app` | `sioyek/` | `~/Library/Application Support/sioyek/{keys,prefs}_user.config` | Academic PDF viewer with custom keybindings (`w` select rect, `c` add comment, `e` edit, `<D-d>` dark mode). |

---

## Post-Install Checklist on a New Mac

1. **Grant macOS Accessibility & Input Monitoring Permissions** (`System Settings -> Privacy & Security`):
   - **Accessibility**: `AeroSpace`, `Hammerspoon`, `Karabiner-Elements`, `Espanso`, `Homerow`, `Shortcat`, `Maccy`.
   - **Input Monitoring**: `Karabiner-Elements` (`karabiner_grabber`, `karabiner_observer`), `Espanso`.
2. **Configure API Keys for the Hammerspoon Writing Assistant (`Cmd+G`)**:
   - Either sign in to OpenAI in OpenCode (`opencode auth login` — Hammerspoon automatically reads the active key from `~/.local/share/opencode/opencode.db`), **or** add your keys to `~/.zsh_secrets`:
     ```bash
     export OPENAI_API_KEY="sk-..."
     export GEMINI_API_KEY="AIza..."
     ```
3. **Verify Hammerspoon Grammar Assistant**:
   ```bash
   hs -c 'dofile(hs.configdir .. "/grammar_checker_test.lua")'
   ```
