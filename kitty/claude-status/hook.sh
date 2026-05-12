#!/usr/bin/env bash
# Fire a desktop notification when Claude Code wants user attention.
#
# Invoked by Claude Code hooks:
#   hook.sh Stop          → turn complete, your move
#   hook.sh Notification  → CC needs permission / input / etc.
#
# Uses `kitty @ kitten notify`, which routes through kitty's OSC 99 channel
# so the notification is owned by this kitty window — clicking it focuses
# the tab where Claude is running.

set -uo pipefail

event="${1:-}"
hook_json="$(cat 2>/dev/null || true)"

urgency="normal"
sound="system"
ntype="claude-$event"

case "$event" in
  Stop)
    body="finished"
    ;;
  Notification)
    body="$(printf '%s' "$hook_json" | jq -r '.message // empty' 2>/dev/null)"
    [[ -z "$body" ]] && body="needs input"

    shopt -s nocasematch
    case "$body" in
      *permission*|*approve*|*allow*)
        urgency="critical"   # break through Focus / Do Not Disturb
        sound="error"
        ntype="claude-permission" ;;
      *authentic*|*auth\ *)
        urgency="low"
        ntype="claude-auth" ;;
      *)
        # Idle reminders, "Claude is waiting for your input", MCP elicitations.
        sound="error"
        ntype="claude-notification" ;;
    esac
    shopt -u nocasematch
    ;;
  *)
    exit 0
    ;;
esac

kitty_bin="/Applications/kitty.app/Contents/MacOS/kitty"
sock="${KITTY_LISTEN_ON:-}"
[[ -z "$sock" || ! -x "$kitty_bin" ]] && exit 0

project="$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")"
ident="${ntype}-${project//[^a-zA-Z0-9_.-]/_}"

"$kitty_bin" @ --to "$sock" kitten notify \
  --identifier "$ident" \
  --app-name "Claude" \
  --type "$ntype" \
  --urgency "$urgency" \
  --sound-name "$sound" \
  "Claude — $project" "$body" >/dev/null 2>&1 || true

exit 0
