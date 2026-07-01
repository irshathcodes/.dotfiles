# cs: remote-pane cwd reporting + automatic terminal title.
#   preexec -> title = the command being run (so the server tab shows e.g. "pnpm")
#   precmd  -> title = the current dir  (so the shell/path tab shows where you are)
# Sourced from ~/.zshrc. The title runs for any interactive shell; the cwd file
# (used by "open a new pane here") is written only for cs panes (CS_SESSION set).
# nvim/claude set their own titles and override these while they run.
autoload -Uz add-zsh-hook

_cs_title() { printf '\033]2;%s\007' "$1"; }

_cs_precmd() {
  if [[ -n ${CS_SESSION:-} ]]; then
    local d="$HOME/.cache/cs/cwd"; [[ -d $d ]] || mkdir -p "$d"
    print -r -- "$PWD" >| "$d/$CS_SESSION"
  fi
  _cs_title "${PWD:t}"
}
_cs_preexec() { local c=${1[(w)1]}; _cs_title "${c:t}"; }

add-zsh-hook precmd  _cs_precmd
add-zsh-hook chpwd   _cs_precmd
add-zsh-hook preexec _cs_preexec
_cs_precmd
