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
bindkey -e  # force emacs keybindings (EDITOR=nvim auto-enables vi mode otherwise)

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

# dotfiles secrets (gitignored) — used by tools like pi's mcp.json ${VAR} interpolation
[[ -f ~/.dotfiles/.env ]] && source ~/.dotfiles/.env

# Enable vi mode in zsh
# bindkey -v
# export KEYTIMEOUT=1



# nvm — lazy loaded. The default version's bin is put on PATH instantly (~0ms);
# the full `nvm` command sources nvm.sh only on first invocation (~230ms, paid once,
# on demand). Previously nvm_auto ran on every shell start and cost ~half of startup.
export NVM_DIR="$HOME/.nvm"
if [ -r "$NVM_DIR/alias/default" ]; then
  export PATH="$NVM_DIR/versions/node/$(cat "$NVM_DIR/alias/default")/bin:$PATH"
fi
nvm() {
  unset -f nvm
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # nvm bash_completion
  nvm "$@"
}


# Set up fzf key bindings and fuzzy completion
source <(fzf --zsh)

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

 ghdiff() {                                                                                                            
    local pr=$1                                                   
    [[ -z "$pr" ]] && { echo "usage: ghdiff <pr>"; return 1; }
                                                                                                                        
    local base
    base=$(gh pr view "$pr" --json baseRefName -q .baseRefName) || return 1                                             
                                                                                                                        
    local tmp; tmp=$(mktemp -d -t "ghdiff-$pr")
    git fetch origin "pull/$pr/head:refs/ghdiff/$pr" >/dev/null 2>&1 || return 1                                        
    git fetch origin "$base" >/dev/null 2>&1                                                                            
                                                                                                                        
    git worktree add --detach "$tmp/base" "origin/$base" >/dev/null                                                     
    git worktree add --detach "$tmp/head" "refs/ghdiff/$pr" >/dev/null                                                  
                                                                                                                        
    kitten diff "$tmp/base" "$tmp/head"
                                                                                                                        
    git worktree remove --force "$tmp/head" >/dev/null            
    git worktree remove --force "$tmp/base" >/dev/null
    git update-ref -d "refs/ghdiff/$pr"                                                                                 
    rm -rf "$tmp"
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

# Completions: initialize zsh's completion system once, fast. (This used to load only as
# a side effect of bun's completion script, which has been removed.) -C reuses the cached
# ~/.zcompdump and skips the slow per-file security audit; the dump is rebuilt at most
# once a day so completions for newly installed tools still get picked up.
autoload -Uz compinit
_zdump_stale=( ${ZDOTDIR:-$HOME}/.zcompdump(N.mh+24) )
if (( $#_zdump_stale )); then compinit; else compinit -C; fi
unset _zdump_stale

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/irshath/.lmstudio/bin"
# End of LM Studio CLI section

export PATH="$HOME/.local/bin:$PATH"

# Zsh autosuggestions
source $HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh
bindkey '^Y' autosuggest-accept




export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
# pyenv — lazy loaded. The shims dir on PATH is what makes `python`/`pip` resolve to your
# pyenv version (3.13.0) instead of macOS's old system python (3.9.6) — so it stays
# instant. The expensive `pyenv init` (which runs `pyenv rehash`, ~70ms, on every startup)
# is deferred to the first actual `pyenv` command. Run `pyenv rehash` yourself after
# installing a tool/version that adds new executables.
export PATH="$PYENV_ROOT/shims:$PATH"
export PYENV_SHELL=zsh
pyenv() {
  unset -f pyenv
  eval "$(command pyenv init - zsh)"
  pyenv "$@"
}


# pyenv-virtualenv: skip the ~25ms `eval "$(pyenv virtualenv-init -)"` subprocess and
# just put its shims on PATH directly. This omits the auto-activation precmd hook (which
# wasn't functioning under the previous bash-mode init anyway). If you later want
# virtualenvs to auto-activate on cd, restore: eval "$(pyenv virtualenv-init -)"
export PATH="$PYENV_ROOT/plugins/pyenv-virtualenv/shims:$PATH"
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"

export PATH="$HOME/.local/bin:$PATH"

# opencode
export PATH=/Users/irshath/.opencode/bin:$PATH
