#!/usr/bin/env bash

# Shows open kitty sessions in fzf and switches using goto_session
# Adds a vim-like "mode":
# - Normal mode (default): j/k move, d closes, enter opens, i enters insert mode, esc quits
# - Insert mode: type to filter, enter opens, esc returns to normal mode

set -euo pipefail

default_mode="normal"

set_cursor_block() {
  # DECSCUSR: steady block
  printf '\e[2 q' >/dev/tty
}

set_cursor_bar() {
  # DECSCUSR: steady bar
  printf '\e[6 q' >/dev/tty
}

# Always restore to bar on exit
trap 'set_cursor_bar' EXIT

kitty_bin="/Applications/kitty.app/Contents/MacOS/kitty"

# Kanagawa theme colors
base_color="\033[38;2;192;163;110m"    # #c0a36e (yellow) — non-focused sessions
current_color="\033[38;2;118;148;106m"  # #76946a (green) — focused session
reset_color="\033[0m"

fzf_colors="bg:#1f1f28,fg:#dcd7ba"
fzf_colors+=",hl:#c0a36e,hl+:#c0a36e"
fzf_colors+=",info:#7e9cd8,header:#7e9cd8"
fzf_colors+=",prompt:#76946a"
fzf_colors+=",pointer:#e6c384"
fzf_colors+=",marker:#7fb4ca"
fzf_colors+=",spinner:#938aa9"
fzf_colors+=",fg+:#dcd7ba"
fzf_colors+=",bg+:#2d4f67"
fzf_colors+=",gutter:#1f1f28"

# Requirements
if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf is not installed or not in PATH."
  echo "Install (brew): brew install fzf"
  exit 1
fi

if [[ ! -x "$kitty_bin" ]]; then
  echo "kitty binary not found at: $kitty_bin"
  exit 1
fi

sock="$(ls /tmp/kitty-* 2>/dev/null | head -n1 || true)"
if [[ -z "${sock:-}" ]]; then
  echo "No kitty sockets found in /tmp (kitty not running, or remote control not available)."
  exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
sessions_file="/tmp/kitty-sessions.json"

query_sessions() {
  "$kitty_bin" @ --to "unix:${sock}" kitten "${script_dir}/list-sessions.py" 2>/dev/null
  sleep 0.3
}

build_menu_lines() {
  query_sessions

  if [[ ! -f "$sessions_file" ]]; then
    return 1
  fi

  local active sessions
  active="$(python3 -c "import json; d=json.load(open('$sessions_file')); print(d.get('active',''))")"
  sessions="$(python3 -c "import json; d=json.load(open('$sessions_file')); print('\n'.join(d.get('sessions',[])))")"

  if [[ -z "${sessions:-}" ]]; then
    return 1
  fi

  local idx=0
  while IFS= read -r name; do
    idx=$((idx + 1))
    if [[ "$name" == "$active" ]]; then
      printf "%d\t%s\t${current_color}%s${reset_color}  (active)\n" "$idx" "$name" "$name"
    else
      printf "%d\t%s\t${base_color}%s${reset_color}\n" "$idx" "$name" "$name"
    fi
  done <<< "$sessions"
}

# Set the startup mode
mode="$default_mode"
fzf_start_pos=""

while true; do
  menu_lines="$(build_menu_lines || true)"
  if [[ -z "${menu_lines:-}" ]]; then
    echo "No sessions found."
    exit 1
  fi

  fzf_out=""
  fzf_rc=0

  if [[ "$mode" == "normal" ]]; then
    # Normal mode:
    # - Search disabled (typing doesn't filter)
    # - j/k move
    # - d closes session
    # - enter opens session
    # - i enters insert mode
    # - esc quits
    # - --no-clear avoids a visible screen "flash"
    #   - We exit one fzf instance and immediately start another when switching modes
    #   - Prevents fzf from clearing/restoring the screen on exit
    set_cursor_block
    set +e
    fzf_start_pos_opt=()
    if [[ -n "${fzf_start_pos:-}" && "$fzf_start_pos" -gt 1 ]]; then
      fzf_start_action="down"
      for ((i = 3; i <= fzf_start_pos; i++)); do
        fzf_start_action+="+down"
      done
      # Workaround for older fzf where start:* actions are ignored.
      # Based on https://github.com/junegunn/fzf/issues/4559
      fzf_start_pos_opt=(--bind "result:${fzf_start_action}")
    fi
    fzf_out="$(
      printf "%s\n" "$menu_lines" |
        fzf --ansi --height=100% --reverse \
          --header="Normal: j/k move, d close, enter open, i insert, esc quit" \
          --prompt="List Open Kitty Sessions > " \
          --no-multi --disabled \
          --with-nth=3.. \
          --expect=enter,d,i,esc \
          --bind 'j:down,k:up' \
          --bind 'enter:accept,d:accept,i:accept' \
          --bind 'esc:abort' \
          --no-clear \
          --color="$fzf_colors" \
          ${fzf_start_pos_opt[@]+"${fzf_start_pos_opt[@]}"}

    )"
    fzf_rc=$?
    fzf_start_pos=""
    set -e
  else
    # Insert mode:
    # - Search enabled (type to filter)
    # - enter opens session
    # - esc returns to normal mode
    # - --no-clear avoids a visible screen "flash"
    #   - We exit one fzf instance and immediately start another when switching modes
    #   - Prevents fzf from clearing/restoring the screen on exit

    set_cursor_bar
    set +e
    fzf_out="$(
      printf "%s\n" "$menu_lines" |
        fzf --ansi --height=100% --reverse \
          --header="Insert: type to filter, enter open, esc normal" \
          --prompt="List Open Kitty Sessions > " \
          --no-multi \
          --with-nth=3.. \
          --expect=enter,esc \
          --bind 'enter:accept' \
          --bind 'esc:abort' \
          --no-clear \
          --color="$fzf_colors"
    )"
    fzf_rc=$?
    set -e
  fi

  # If fzf aborted and gave no output, treat it like "esc"
  if [[ $fzf_rc -ne 0 && -z "${fzf_out:-}" ]]; then
    key="esc"
    sel=""
  else
    key="$(printf "%s\n" "$fzf_out" | head -n1)"
    sel="$(printf "%s\n" "$fzf_out" | sed -n '2p' || true)"
  fi

  # Selection line is: idx<TAB>session_name<TAB>pretty_display
  selected_title=""
  selected_index=""
  if [[ -n "${sel:-}" ]]; then
    selected_index="$(printf "%s" "$sel" | awk -F'\t' '{print $1}')"
    selected_title="$(printf "%s" "$sel" | awk -F'\t' '{print $2}')"
  fi

  if [[ "$mode" == "insert" && "$key" == "esc" ]]; then
    mode="normal"
    continue
  fi

  if [[ "$mode" == "normal" && "$key" == "esc" ]]; then
    exit 0
  fi

  if [[ "$mode" == "normal" && "$key" == "i" ]]; then
    mode="insert"
    continue
  fi

  if [[ -z "${selected_title:-}" ]]; then
    # Nothing selected (likely esc)
    if [[ "$mode" == "normal" ]]; then
      exit 0
    fi
    mode="normal"
    continue
  fi

  if [[ "$mode" == "normal" && "$key" == "d" ]]; then
    if [[ "${selected_index:-}" =~ ^[0-9]+$ ]]; then
      total_lines="$(printf "%s\n" "$menu_lines" | awk 'END{print NR}')"
      if [[ -n "${total_lines:-}" && "$selected_index" -ge "$total_lines" ]]; then
        fzf_start_pos=$((selected_index - 1))
      else
        fzf_start_pos=$selected_index
      fi
      if [[ "$fzf_start_pos" -lt 1 ]]; then
        fzf_start_pos=1
      fi
    fi
    "$kitty_bin" @ --to "unix:${sock}" action close_session "$selected_title" >/dev/null 2>&1 || true
    continue
  fi

  if [[ "$key" == "enter" ]]; then
    "$kitty_bin" @ --to "unix:${sock}" action goto_session "$selected_title"
    exit 0
  fi

  # Fallback behavior:
  # - In insert mode, abort returns here -> go back to normal
  # - In normal mode, unknown key -> exit
  if [[ "$mode" == "insert" ]]; then
    mode="normal"
    continue
  fi

  exit 0
done
