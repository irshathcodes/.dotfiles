#!/bin/sh
# kittymux.sh <verb>  -  one context-aware dispatcher for all wrapped kitty keys.
#
# It inspects the ACTIVE window (kitty's is_active, not OS focus), decides
# remote-vs-local, and branches:
#   - remote pane (a cs/zmx pane launched via remote-attach.sh): do the
#     zmx-aware thing (create/kill the session, re-save the project layout).
#   - local pane: fall through to plain native kitty behavior.
#
# Verbs:
#   split        new split   (remote: fresh persistent zmx session in the pane's
#                             cwd + save layout; local: native split)
#   tab          new tab     (same, as a tab)
#   close-pane   close active window (remote: also kill its zmx session + save)
#   close-tab    close active tab    (remote: also kill all its zmx sessions + save)
#   save         re-save the active project's remote session file
#
# zmx is touched ONLY here (from shortcuts). Quitting kitty / closing the OS
# window / the tab-bar X never run this, so sessions persist unless you press a
# kill shortcut. That is the whole point.
#
# The layout is saved by GENERATING the session file directly from `ls` (not via
# kitty's save_as_session action, which opens the saved file in an editor).
#
# Launched by kitty as:  launch --type=background kittymux.sh <verb>
set -eu

LOG=/tmp/kittymux.log
exec 2>>"$LOG"
verb="${1:-}"
echo "--- $(date) verb=$verb listen=${KITTY_LISTEN_ON:-none}" >&2

# A background launch inherits a minimal PATH (/usr/bin:/bin), so Homebrew's
# jq/kitten (Apple Silicon /opt/homebrew, Intel /usr/local) would be invisible.
# Prepend the common locations, then resolve each tool with a hard fallback.
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH
KITTEN=$(command -v kitten 2>/dev/null || true); [ -n "$KITTEN" ] || KITTEN=/Applications/kitty.app/Contents/MacOS/kitten
JQ=$(command -v jq 2>/dev/null || true);         [ -n "$JQ" ]     || JQ=/usr/bin/jq
SSH=$(command -v ssh 2>/dev/null || true);        [ -n "$SSH" ]    || SSH=/usr/bin/ssh
HOST="${REMOTE_HOST:-moideen}"
RA="$HOME/.config/kitty/remote-attach.sh"
STATE_DIR="$HOME/.local/state/kittymux"

# Projects that get a seeded default layout. Add a name here when you wire up a
# new cmd+j <letter>. (The cmd+j keys open these via native goto_session.)
# Names must match the remote cs registry (~/.config/cs/projects on the server)
# and the goto_session filenames in kitty.conf. Order mirrors cmd+j p/f/n/c/g/b.
PROJECTS="px-ui frontend spend-management-service candidate-app gql buildkit"

sessfile() { echo "$STATE_DIR/$1.kitty-session"; }

# Default 4-tab layout, generated when a project has no saved file yet (fresh
# machine / first open). The seed lives as CODE, not a checked-in file, so a new
# project needs nothing on disk. Same directive format as save_project so a
# later save round-trips cleanly. edit is focused on open.
seed_default() {
  _p="$1"
  printf 'new_tab\nlayout stack\nlaunch --var=cs_session=%s.edit --var=cs_project=%s %s %s edit\nfocus\n\n' "$_p" "$_p" "$RA" "$_p"
  printf 'new_tab\nlayout stack\nlaunch --var=cs_session=%s.cc --var=cs_project=%s %s %s cc\n\n' "$_p" "$_p" "$RA" "$_p"
  printf 'new_tab\nlayout grid\nlaunch --var=cs_session=%s.srv --var=cs_project=%s %s %s srv\n\n' "$_p" "$_p" "$RA" "$_p"
  printf 'new_tab\nlayout grid\nlaunch --var=cs_session=%s.sh --var=cs_project=%s %s %s sh\n' "$_p" "$_p" "$RA" "$_p"
}

# seed-all: ensure every project has a state file, creating any missing one from
# the default template. Pure local file writes - no kitty socket, no ssh - so it
# is safe and fast to run from install.sh (or by hand) with no kitty running.
# This is what guarantees `cmd+j <letter>` (a native goto_session) always finds a
# file to open. Handled here, before the kitty-dependent setup below.
if [ "$verb" = seed-all ]; then
  mkdir -p "$STATE_DIR"
  for _p in $PROJECTS; do
    _f="$(sessfile "$_p")"
    if [ -s "$_f" ]; then echo "seed-all: ok $_f" >&2
    else seed_default "$_p" > "$_f"; echo "seed-all: created $_f" >&2; fi
  done
  exit 0
fi

# Find the live control socket. Background launches do NOT inherit
# KITTY_LISTEN_ON, and a restarted kitty can leave a stale socket behind, so we
# test each candidate for a working connection instead of taking the first.
to="${KITTY_LISTEN_ON:-}"
if [ -z "$to" ]; then
  for s in /tmp/kitty-*; do
    [ -S "$s" ] || continue
    if "$KITTEN" @ --to "unix:$s" ls >/dev/null 2>&1; then to="unix:$s"; break; fi
  done
fi
k() { "$KITTEN" @ ${to:+--to "$to"} "$@"; }

ls_json=$(k ls 2>/dev/null || true)

# active OS window -> active tab -> active window (the pane the key was pressed in)
aw=$(printf '%s' "$ls_json" | "$JQ" -c '[.[] | select(.is_active) | .tabs[] | select(.is_active) | .windows[] | select(.is_active)][0] // empty' 2>/dev/null || true)
at=$(printf '%s' "$ls_json" | "$JQ" -c '[.[] | select(.is_active) | .tabs[] | select(.is_active)][0] // empty' 2>/dev/null || true)

# A window's cs session/project: prefer the user_vars we set on new panes; else
# parse the remote-attach.sh launch cmdline (covers the original hand-authored panes).
PROG_SESSION='(.user_vars.cs_session // "") as $v | if $v != "" then $v elif ((.cmdline|type)=="array" and (.cmdline|length)>=4 and (.cmdline[1]|test("remote-attach"))) then (.cmdline[2]+"."+.cmdline[3]) else "" end'
PROG_PROJECT='(.user_vars.cs_project // "") as $v | if $v != "" then $v elif ((.cmdline|type)=="array" and (.cmdline|length)>=3 and (.cmdline[1]|test("remote-attach"))) then .cmdline[2] else "" end'

proj=$(printf '%s' "$aw" | "$JQ" -r "$PROG_PROJECT" 2>/dev/null || true)
session=$(printf '%s' "$aw" | "$JQ" -r "$PROG_SESSION" 2>/dev/null || true)
wid=$(printf '%s' "$aw" | "$JQ" -r '.id // empty' 2>/dev/null || true)
tid=$(printf '%s' "$at" | "$JQ" -r '.id // empty' 2>/dev/null || true)

# Re-query ls fresh (post-action) and generate the project's session file.
# Silent: no editor, no extra window. Only tabs containing a project pane are
# written, and only project panes within them.
save_project() {
  _p="${1:-}"; [ -n "$_p" ] || return 0
  mkdir -p "$STATE_DIR"
  _out="$(sessfile "$_p")"
  _tmp="$_out.tmp.$$"
  # Snapshot ls ONCE and validate it. If ls itself is unavailable (kitty gone /
  # socket glitch) we must NOT rewrite the file - leaving it stale is safe,
  # clobbering it is not. Only a VALID-but-empty capture means the project is
  # genuinely closed (handled below).
  _ls=$(k ls 2>/dev/null || true)
  if [ -z "$_ls" ] || ! printf '%s' "$_ls" | "$JQ" -e 'type=="array"' >/dev/null 2>&1; then
    echo "save $_p: ls unavailable, kept previous file" >&2
    return 0
  fi
  # Walk ALL os-windows (not just the active one, so a project living in a
  # background window still saves). Per tab: emit its ACTUAL current layout so
  # runtime layout switches round-trip. Per pane: carry the cwd (cs_cwd var) so a
  # killed+recreated pane returns to its dir. Emit `focus` only for the active
  # window OF THE ACTIVE TAB, so exactly one focus wins on reopen.
  printf '%s' "$_ls" | "$JQ" -r --arg p "$_p" --arg ra "$RA" '
    def isproj($p): ((.user_vars.cs_project // "") == $p)
      or (((.cmdline|type)=="array") and ((.cmdline|length)>=3) and ((.cmdline[1])|test("remote-attach")) and ((.cmdline[2])==$p));
    def sessname($p): (.user_vars.cs_session // "") as $v
      | if $v != "" then $v
        elif ((.cmdline|type)=="array" and (.cmdline|length>=4) and (.cmdline[1]|test("remote-attach"))) then (.cmdline[2]+"."+.cmdline[3])
        else "" end;
    [ .[] | .tabs[]
      | .is_active as $tabactive
      | select(any(.windows[]; isproj($p)))
      | (.layout) as $lay
      | ("new_tab"),
        ("layout " + $lay),
        ( .windows[] | select(isproj($p)) | . as $w
          | (sessname($p)) as $s
          | ($s | ltrimstr($p + ".")) as $nm
          | (.user_vars.cs_cwd // "") as $cwd
          | ("launch --var=cs_session=" + $s + " --var=cs_project=" + $p
             + (if $cwd != "" then " --var=cs_cwd=" + $cwd else "" end)
             + " " + $ra + " " + $p + " " + $nm
             + (if $cwd != "" then " " + $cwd else "" end)
             + (if ($w.is_active and $tabactive) then "\nfocus" else "" end))
        ),
        ""
    ] | .[]
  ' > "$_tmp" 2>>"$LOG" || { rm -f "$_tmp"; return 0; }
  if grep -q '^launch ' "$_tmp" 2>/dev/null; then
    mv "$_tmp" "$_out"
    echo "saved $_p -> $_out ($(grep -c '^launch ' "$_out") panes)" >&2
  else
    # ls was valid but the project has NO live panes: it is fully closed. Reset
    # to the default template rather than keeping the stale file - keeping it
    # would resurrect the sessions the user just closed on the next cmd+j.
    rm -f "$_tmp"
    seed_default "$_p" > "$_out"
    echo "save $_p: no live panes, reset to default template" >&2
  fi
}

# After a tab is destroyed, every project session shares ONE os-window, so kitty
# focuses the most-recently-active tab across ALL sessions - which can drop you
# into a different project. This focuses the most-recent remaining tab of the
# SAME session ($1) instead. Call it BEFORE the close (we move focus onto the
# sibling, then close the target by id) so there is no visible jump/flicker.
# No-op when the session has no other tab (then kitty's fallback is fine). Uses
# the pre-action snapshot $ls_json; $2 is the id of the tab being closed.
refocus_session() {
  _rp="$1"; _closing="$2"
  [ -n "$_rp" ] && [ -n "$_closing" ] || return 0
  _target=$(printf '%s' "$ls_json" | "$JQ" -r --arg p "$_rp" --argjson closing "$_closing" '
    ( [ .[] | select(.is_active) ][0] ) as $ow
    | ($ow.active_tab_history // []) as $hist
    | ( [ $ow.tabs[] | { id, p: ([ .windows[] | (.user_vars.cs_project // "") ] | map(select(. != "")) | (.[0] // "")) } ] ) as $tabs
    | ( [ $tabs[] | select(.p == $p) | .id ] ) as $sess
    | ( [ $hist[] | select(. != $closing) | select(. as $t | ($sess | index($t)) != null) ] ) as $ord
    | ($ord[-1] // empty)
  ' 2>>"$LOG" || true)
  [ -n "$_target" ] && k focus-tab --match "id:$_target" >/dev/null 2>&1 || true
}

case "$verb" in
  split|tab)
    ltype=window; [ "$verb" = tab ] && ltype=tab
    if [ -z "$proj" ]; then
      echo "local $verb (active pane not remote)" >&2
      if [ "$verb" = tab ]; then
        k launch --type=tab --cwd=current
      else
        k goto-layout stack >/dev/null 2>&1 || true
        k launch --type=window --cwd=current
      fi
      exit 0
    fi
    cwd=$("$SSH" "$HOST" "cat ~/.cache/cs/cwd/$session 2>/dev/null" 2>/dev/null || true)
    # $$ (this dispatcher's PID) disambiguates panes created within the same
    # second - date +%H%M%S alone collided, giving several tabs one shared zmx
    # session (the sh-162440 x3 bug).
    newname="sh-$(date +%H%M%S)-$$"
    # A new TAB must be told to join the current session, else the session-aware
    # tab bar shows it split off. A split (window) inherits its tab's session.
    sessflag=""; [ "$verb" = tab ] && sessflag="--add-to-session ."
    echo "remote $verb proj=$proj from=$session new=$proj.$newname cwd=${cwd:-<root>}" >&2
    if [ -n "$cwd" ]; then
      # cs_cwd var lets save_project persist this dir so a killed+recreated pane
      # returns here instead of the project root.
      k launch --type="$ltype" $sessflag --var "cs_session=$proj.$newname" --var "cs_project=$proj" --var "cs_cwd=$cwd" "$RA" "$proj" "$newname" "$cwd"
    else
      k launch --type="$ltype" $sessflag --var "cs_session=$proj.$newname" --var "cs_project=$proj" "$RA" "$proj" "$newname"
    fi
    save_project "$proj"
    ;;

  close-pane)
    # If this is the tab's LAST window, closing it destroys the tab, so land
    # focus on a same-session sibling first (same one-os-window reason as
    # close-tab). A split among others keeps its tab, so leave focus alone.
    _n=$(printf '%s' "$at" | "$JQ" -r '.windows | length' 2>/dev/null || echo 9)
    [ "$_n" = "1" ] && refocus_session "$proj" "$tid"
    # Close the kitty window FIRST (stops the local reconnect loop so it can't
    # recreate the session), THEN kill the zmx session on the server.
    [ -n "$wid" ] && k close-window --match "id:$wid" >/dev/null 2>&1 || true
    if [ -n "$session" ]; then
      echo "remote close-pane: kill zmx $session" >&2
      "$SSH" "$HOST" "zmx kill '$session'" >/dev/null 2>&1 || true
      save_project "$proj"
    else
      echo "local close-pane wid=$wid" >&2
    fi
    ;;

  close-tab)
    # Collect every remote session in the active tab BEFORE closing it.
    sessions=$(printf '%s' "$at" | "$JQ" -r '.windows[] | (.user_vars.cs_session // "") as $v | if $v != "" then $v elif ((.cmdline|type)=="array" and (.cmdline|length)>=4 and (.cmdline[1]|test("remote-attach"))) then (.cmdline[2]+"."+.cmdline[3]) else "" end' 2>/dev/null | grep -v '^$' || true)
    tproj=$(printf '%s' "$at" | "$JQ" -r '[.windows[] | (.user_vars.cs_project // "") as $v | if $v != "" then $v elif ((.cmdline|type)=="array" and (.cmdline|length)>=3 and (.cmdline[1]|test("remote-attach"))) then .cmdline[2] else "" end] | map(select(.!="")) | .[0] // ""' 2>/dev/null || true)
    # Land focus on a same-session sibling BEFORE closing, so we never bounce
    # into another project's session (all sessions share one os-window).
    refocus_session "$tproj" "$tid"
    [ -n "$tid" ] && k close-tab --match "id:$tid" >/dev/null 2>&1 || true
    if [ -n "$sessions" ]; then
      echo "remote close-tab: kill zmx $(echo $sessions | tr '\n' ' ')" >&2
      # $sessions is newline-separated; leave it UNQUOTED so each name becomes a
      # separate argument (ssh rejoins them with spaces -> `zmx kill a b c`).
      # Quoting it would send one blob with embedded newlines and only the first
      # session would be killed, leaking the rest.
      # shellcheck disable=SC2086
      "$SSH" "$HOST" zmx kill $sessions >/dev/null 2>&1 || true
      save_project "$tproj"
    else
      echo "local close-tab tid=$tid" >&2
    fi
    ;;

  open)
    # Manual / fresh-machine seeder ONLY. The hot key `cmd+j p` is a native
    # goto_session (in-process, instant) - do NOT route it through here, the
    # fork + remote-control add latency. Seeds the default layout if the project
    # has no file yet, then opens it.
    _p="${2:-}"; [ -n "$_p" ] || { echo "open: need a project name" >&2; exit 2; }
    mkdir -p "$STATE_DIR"
    _f="$(sessfile "$_p")"
    [ -s "$_f" ] || { seed_default "$_p" > "$_f"; echo "open $_p: seeded default -> $_f" >&2; }
    # `@ action` wants the action + its args as one string (kitty.conf form).
    k action "goto_session $_f"
    ;;

  save)
    if [ -n "$proj" ]; then save_project "$proj"; else echo "save: active pane not remote" >&2; fi
    ;;

  prune)
    # Manual cleanup. For the projects you CURRENTLY have open, kill their zmx
    # sessions that have no live kitty window (orphans left by exit/drop/restart),
    # then sweep stale cwd-files. Scoped to open projects so a session you
    # intentionally detached from another project is never touched. Output goes
    # to stdout so the launching overlay shows what happened.
    live=$(printf '%s' "$ls_json" | "$JQ" -r '[.[].tabs[].windows[]
      | (.user_vars.cs_session // "") as $v
      | if $v!="" then $v
        elif ((.cmdline|type)=="array" and (.cmdline|length)>=4 and (.cmdline[1]|test("remote-attach"))) then (.cmdline[2]+"."+.cmdline[3])
        else empty end] | unique | .[]' 2>/dev/null || true)
    openprojs=$(printf '%s' "$ls_json" | "$JQ" -r '[.[].tabs[].windows[]
      | (.user_vars.cs_project // "") as $v
      | if $v!="" then $v
        elif ((.cmdline|type)=="array" and (.cmdline|length)>=3 and (.cmdline[1]|test("remote-attach"))) then .cmdline[2]
        else empty end] | unique | .[]' 2>/dev/null || true)
    allz=$("$SSH" "$HOST" "zmx ls --short" 2>/dev/null || true)
    kill_list=""
    for s in $allz; do
      p=${s%%.*}
      printf '%s\n' "$openprojs" | grep -qx "$p" || continue   # project not open -> leave alone
      printf '%s\n' "$live" | grep -qx "$s" && continue         # has a live window -> keep
      kill_list="$kill_list $s"
    done
    if [ -n "$kill_list" ]; then
      echo "pruning orphan sessions:$kill_list"
      # shellcheck disable=SC2086
      "$SSH" "$HOST" "zmx kill $kill_list" >/dev/null 2>&1 || true
    else
      echo "no orphan sessions for open projects ($(echo $openprojs))"
    fi
    # sweep cwd-files whose session no longer exists (harmless bookkeeping cruft).
    # `a=$(zmx ls) || exit 0`: if zmx is unavailable (not on PATH / mid-restart)
    # the listing FAILS -> bail without deleting, else an empty list would make
    # every cwd-file look orphaned and wipe them all. An empty list from a
    # SUCCESSFUL zmx (genuinely no sessions) correctly sweeps all stale files.
    "$SSH" "$HOST" 'd=~/.cache/cs/cwd; [ -d "$d" ] || exit 0; a=$(zmx ls --short) || exit 0; for f in "$d"/*; do [ -e "$f" ] || continue; b=$(basename "$f"); printf "%s\n" "$a" | grep -qx "$b" || rm -f "$f"; done' >/dev/null 2>&1 || true
    # refresh the open projects files so the killed sessions leave the layout too
    for p in $openprojs; do save_project "$p"; done
    printf 'done. press enter to close.'; read _ 2>/dev/null || true
    ;;

  *)
    echo "kittymux: unknown verb '$verb'" >&2
    exit 2
    ;;
esac
