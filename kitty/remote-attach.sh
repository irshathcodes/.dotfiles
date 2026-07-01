#!/bin/sh
# Mac-side launcher for a kitty tab/pane attached to a remote zmx session.
#
# Uses plain "ssh -t". The kitty ssh kitten's connection sharing multiplexes
# all tabs over one SSH master and mis-sized the PTY, which made Claude/nvim
# render wider than the window (garbled, wrapped frame). Colors are handled
# inside the session by cs (TERM=xterm-256color + COLORTERM=truecolor), so the
# kitten is not needed for color.
#
# Exit-status contract (this is why we can auto-reconnect safely):
#   0    clean detach (ctrl-\) or the shell exited -> we are done, stop.
#   255  ssh transport failure (network drop / sleep / host down) -> RETRY;
#        this is the "close the lid, come back later, reattach" path.
#   else remote command failed (cs not installed = 127, unknown project = 1,
#        etc.) -> a SETUP error, NOT a network drop. Surface it and stop
#        instead of spinning "reconnecting..." forever on a misconfiguration.
# Keepalives live in ~/.ssh/config for the host so a dead connection fails fast
# (~9s) instead of hanging on the TCP timeout.
#
#   usage: remote-attach.sh <project> [name] [dir]
#   dir : optional start dir (passed to cs) for "open a new pane in this dir".
host="${REMOTE_HOST:-moideen}"
project="$1"
name="${2:-sh}"
dir="${3:-}"

# Baseline tab title: a sensible name shown until the remote program/shell sets
# its own via OSC (prevents the tab reading "remote-attach.sh"). Content wins:
# claude shows its task, the shell hook shows the running command / cwd.
case "$name" in
  edit) _t=nvim ;; cc) _t=claude ;; srv) _t=server ;; *) _t=shell ;;
esac
printf '\033]2;%s\007' "$_t"

run() {
  if [ -n "$dir" ]; then
    ssh -t "$host" cs "$project" "$name" "$dir"
  else
    ssh -t "$host" cs "$project" "$name"
  fi
}

while :; do
  run; rc=$?
  [ "$rc" -eq 0 ] && break
  if [ "$rc" -eq 255 ]; then
    printf '\r\n[%s.%s] connection lost, reconnecting (Ctrl-C to stop)...\r\n' "$project" "$name"
    sleep 1
  else
    printf '\r\n[%s.%s] cs exited %s - not a connection drop.\r\n' "$project" "$name" "$rc"
    printf 'Likely setup: unknown project, or cs not installed on %s.\r\n' "$host"
    printf 'Press Enter to close this pane.\r\n'
    read _ || true
    break
  fi
done
