#!/usr/bin/env bash
# Fire a desktop notification when Claude Code wants user attention.
#
# Invoked by Claude Code hooks:
#   hook.sh Stop          → turn complete, your move
#   hook.sh Notification  → CC needs permission / input / etc.
#
# Uses macOS notifications directly instead of kitty's OSC 99 channel. Keeping
# the notification outside kitty avoids stealing focus from the active split.

set -uo pipefail

event="${1:-}"
hook_json="$(cat 2>/dev/null || true)"

urgency="normal"
sound="Glass"
ntype="claude-$event"

case "$event" in
  Stop)
    body="finished"
    ;;
  Notification)
    body="$(printf '%s' "$hook_json" | jq -r '.message // empty' 2>/dev/null)"
    [[ -z "$body" ]] && body="needs input"
    notification_type="$(printf '%s' "$hook_json" | jq -r '.notification_type // empty' 2>/dev/null)"

    case "$notification_type" in
      permission_prompt)
        urgency="critical"
        sound="Basso"
        ntype="claude-permission" ;;
      idle_prompt)
        # CC fires this ~60s after Stop as an idle nudge — redundant with the
        # Stop notification we already sent. Skip to avoid double-pinging.
        exit 0 ;;
      auth_success)
        urgency="low"
        sound="Glass"
        ntype="claude-auth" ;;
      elicitation_dialog|elicitation_complete|elicitation_response)
        # MCP elicitations and other one-off messages.
        sound="Basso"
        ntype="claude-notification" ;;
      *)
        shopt -s nocasematch
        case "$body" in
          *permission*|*approve*|*allow*)
            urgency="critical"
            sound="Basso"
            ntype="claude-permission" ;;
          *waiting*)
            shopt -u nocasematch
            exit 0 ;;
          *authentic*|*auth\ *)
            urgency="low"
            sound="Glass"
            ntype="claude-auth" ;;
          *)
            sound="Basso"
            ntype="claude-notification" ;;
        esac
        shopt -u nocasematch
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac

project="$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")"
title="Claude — $project"

if command -v osascript >/dev/null 2>&1; then
  osascript \
    -e 'on run argv' \
    -e 'display notification (item 2 of argv) with title (item 1 of argv) sound name (item 3 of argv)' \
    -e 'end run' \
    "$title" "$body" "$sound" >/dev/null 2>&1 || true
fi

exit 0
