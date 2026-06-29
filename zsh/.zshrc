# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
    git                         # Git shortcuts and features
    zsh-autosuggestions        # Fish-like autosuggestions
    zsh-syntax-highlighting    # Fish-like syntax highlighting
    autojump                   # Smart directory jumping
)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# If we are in the DevContainer, override the Powerlevel10k prompt symbol to '$'
if [[ -d "/workspaces/AgentDojo" ]] || [[ -n "$CLAUDE_CODE_USE_VERTEX" ]]; then
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='$'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='$'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='$'
fi

# Set up fzf key bindings and fuzzy completion
if [ -f ~/.fzf.zsh ]; then
  # Mac Homebrew default installation
  source ~/.fzf.zsh
elif [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
  # Debian / Ubuntu (DevContainer) via apt
  source /usr/share/doc/fzf/examples/key-bindings.zsh
  source /usr/share/doc/fzf/examples/completion.zsh
else
  # Fallback for newer fzf versions
  source <(fzf --zsh 2>/dev/null) || true
fi
# Ollama Command Helper Configuration
export ZSH_OLLAMA_MODEL="vitali87/shell-commands-qwen2-1.5b:latest"

function set_ollama_model {
    if [[ $# -eq 0 ]]; then
        echo "Current model: $ZSH_OLLAMA_MODEL"
        echo "Available models:"
        ollama list | awk 'NR>1 {print $1}'
    else
        export ZSH_OLLAMA_MODEL="$1"
        echo "Ollama model set to: $ZSH_OLLAMA_MODEL"
    fi
}

compdef '_values "models" $(ollama list | awk '\''NR>1 {print $1}'\'')' set_ollama_model

function ollama_command_helper {
    local query="$BUFFER"
    BUFFER=""
    echo -e "\n🤔 \e[34mAsking Ollama (using model: $ZSH_OLLAMA_MODEL)...\e[0m"
    
    local result
    result=$(~/.config/zsh/ollama_env/venv/bin/python3 ~/.config/zsh/ollama_env/ollama_helper.py "$query" 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo -e "\e[31m❌ No command generated.\e[0m"
        return 1
    fi
    
    local user_query command
    user_query=$(printf '%s\n' "$result" | jq -r '.user_query')
    command=$(printf '%s\n' "$result" | jq -r '.command')
    
    echo -e "\e[33mYour query:\e[0m $user_query"
    echo -e "\e[32mGenerated command:\e[0m $command"
    
    local yn
    while true; do
        echo -n "Execute? [y/N] "
        read -k 1 yn
        case $yn in
            [Yy]* ) 
                echo
                eval "$command"
                break
                ;;
            [Nn]* | $'\n' )
                echo
                echo "Aborted."
                break
                ;;
            * )
                ;;
        esac
    done
    
    zle reset-prompt
}

zle -N ollama_command_helper
bindkey '^B' ollama_command_helper   
export ZSH_OLLAMA_MODEL="qwen3:14b"


### 1Password
eval "$(op completion zsh)"; compdef _op op

#################
### Aliases
#################
alias lg='lazygit'
function gemini-docker {
    local tty_args=""
    if [ -t 0 ]; then
        tty_args="--tty"
    fi

    docker run -i ${tty_args} --rm \
        -v "$(pwd):/home/gemini/workspace" \
        -v "$HOME/.gemini:/home/gemini/.gemini" \
        -e DEFAULT_UID=$(id -u) \
        -e DEFAULT_GID=$(id -g) \
        -e GEMINI_API_KEY=$GEMINI_API_KEY \
        -e TERM=$TERM \
        tgagor/gemini-cli "$@"
        # -e COLORTERM=truecolor \
}

#################
### Envs
#################
# API Keys werden aus einer sicheren, lokalen Datei geladen, die NICHT auf GitHub landet
if [ -f "$HOME/.zsh_secrets" ]; then
    source "$HOME/.zsh_secrets"
fi
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# claude code
export CLAUDE_CODE_USE_VERTEX=1
export ANTHROPIC_VERTEX_PROJECT_ID=aipril-455019
export ANTHROPIC_VERTEX_LOCATION="global"

export PATH="$HOME/.cabal/bin:$HOME/.ghcup/bin:$PATH"


# Automatically activate Python virtual environment (.venv) if it exists in the current directory
# or any parent directory.
function auto_activate_venv() {
    # If we are already in a virtualenv, and we left its directory, deactivate it
    if [[ -n "$VIRTUAL_ENV" ]]; then
        parentdir="$(dirname "$VIRTUAL_ENV")"
        if [[ "$PWD"/ != "$parentdir"/* && "$PWD" != "$parentdir" ]]; then
            deactivate
        fi
    fi

    # If we are not in a virtualenv, look for .venv
    if [[ -z "$VIRTUAL_ENV" ]]; then
        local current_dir="$PWD"
        while [[ "$current_dir" != "/" ]]; do
            if [[ -f "$current_dir/.venv/bin/activate" ]]; then
                source "$current_dir/.venv/bin/activate"
                break
            fi
            current_dir="$(dirname "$current_dir")"
        done
    fi
}

# Run the check every time the directory changes
autoload -U add-zsh-hook
add-zsh-hook chpwd auto_activate_venv

# Also run it once when the shell starts
auto_activate_venv


# AgentDojo Pipeline Tools (Only load if inside the DevContainer / if the file exists)
if [ -f "/workspaces/AgentDojo/tools/vd_pipeline.sh" ]; then
    source "/workspaces/AgentDojo/tools/vd_pipeline.sh"
fi


# Automatically load .env file if it exists in the workspace
local env_file="/workspaces/AgentDojo/.env"
if [ -f "$env_file" ]; then
    set -a
    source "$env_file"
    set +a
fi

# --- Cross-Environment Clipboard (macOS & Dev Container) ---
# Kopiert den Input in die System-Zwischenablage.
# Nutzung: echo "hallo" | cb
cb() {
  if command -v pbcopy >/dev/null 2>&1; then
    # Host (macOS)
    pbcopy
  else
    # Dev Container / Linux (via OSC 52 Escape Sequence)
    # Wird vom integrierten VS Code Terminal, WezTerm, iTerm2 etc. direkt an das macOS Clipboard weitergeleitet
    printf "\033]52;c;%s\007" "$(cat | base64 | tr -d '\n' | tr -d '\r')"
  fi
}
alias clip="cb"
