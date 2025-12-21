# Add deno completions to search path
if [[ ":$FPATH:" != *":/Users/irshath/.zsh/completions:"* ]]; then export FPATH="/Users/irshath/.zsh/completions:$FPATH"; fi

export CLICOLOR=1
export LSCOLORS=ExFxBxDxCxegedabagacad

# Git branch in prompt
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' (%b)'
zstyle ':vcs_info:*' enable git
setopt PROMPT_SUBST

export PS1="%B%F{blue}%~%f%b%F{yellow}\${vcs_info_msg_0_}%f "

export EDITOR="nvim"

# History configuration
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt INC_APPEND_HISTORY     # Write to history immediately, but don't share
setopt HIST_SAVE_BY_COPY      # Write to history file safely (prevents corruption)
setopt HIST_EXPIRE_DUPS_FIRST # Expire duplicate entries first when trimming
setopt HIST_IGNORE_DUPS       # Don't record an entry that was just recorded again
setopt HIST_FIND_NO_DUPS      # Don't display duplicates when searching
setopt HIST_IGNORE_SPACE      # Don't record entries starting with a space


[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases

# Enable vi mode in zsh
# bindkey -v
# export KEYTIMEOUT=1



# nvm stuff
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


# Set up fzf key bindings and fuzzy completion
source <(fzf --zsh)
source ~/.dotfiles/fzf-commands.sh

# Custom FZF keybindings (excludes handled by ~/.fdignore)

# ALT+C: CD into a folder starting from home directory
fzf-cd-home-widget() {
  local dir
  dir=$(fd --type d --hidden -L --base-directory ~ | fzf --height 40% --reverse)
  if [[ -n "$dir" ]]; then
    cd ~/"$dir"
    zle reset-prompt
  fi
}
zle -N fzf-cd-home-widget
bindkey '\ec' fzf-cd-home-widget

# ALT+D: CD into a directory from home and open neovim
fzf-cd-nvim-widget() {
  local dir
  dir=$(fd --type d --hidden -L --base-directory ~ | fzf --height 40% --reverse)
  if [[ -n "$dir" ]]; then
    cd ~/"$dir" && nvim .
    zle reset-prompt
  fi
}
zle -N fzf-cd-nvim-widget
bindkey '\ed' fzf-cd-nvim-widget

# ALT+F: Open file from home directory with neovim (no cd)
fzf-file-nvim-widget() {
  local file
  file=$(fd --type f --hidden -L --base-directory ~ | fzf --height 40% --reverse)
  if [[ -n "$file" ]]; then
    nvim ~/"$file" </dev/tty
  fi
  zle reset-prompt
}
zle -N fzf-file-nvim-widget
bindkey '\ef' fzf-file-nvim-widget


##
# Interactive search.
# Usage: `ff` or `ff <folder>`.
ff(){
[[ -n $1 ]] && cd $1 # go to provided folder or noop
RG_DEFAULT_COMMAND="rg -i -l --hidden"

selected=$(
FZF_DEFAULT_COMMAND="rg --files" fzf \
  -m \
  -e \
  --ansi \
  --disabled \
  --reverse \
  --bind "ctrl-a:select-all" \
  --bind "f12:execute-silent:(subl -b {})" \
  --bind "change:reload:$RG_DEFAULT_COMMAND {q} || true" \
  --preview "rg -i --pretty --context 2 {q} {}" | cut -d":" -f1,2
)

[[ -n $selected ]] && subl $selected # open multiple files in editor
}

# switch between local git branches
gcb() {
  local branches branch
  branches=$(git --no-pager branch -vv) &&
  branch=$(echo "$branches" | fzf +m) &&
  git checkout $(echo "$branch" | awk '{print $1}' | sed "s/.* //")
}


# Fuzzy search and open any file on neovim
fe() {
  IFS=$'\n' files=($(fzf --query="$1" --multi --select-1 --exit-0 --preview="bat --color=always {}"))
  [[ -n "$files" ]] && ${EDITOR:-nvim} "${files[@]}"
}

#
. "/Users/irshath/.deno/env"
# pnpm
export PNPM_HOME="/Users/irshath/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
#

export PATH="$PATH:/$HOME/.dotfiles/scripts"

# bun completions
[ -s "/Users/irshath/.bun/_bun" ] && source "/Users/irshath/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/irshath/.lmstudio/bin"
# End of LM Studio CLI section

export PATH="$HOME/.local/bin:$PATH"

# Zsh autosuggestions
source $HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh




export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"


# Load pyenv-virtualenv automatically by adding
# the following to ~/.bashrc:

eval "$(pyenv virtualenv-init -)"
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"

export PATH="$HOME/.local/bin:$PATH"
