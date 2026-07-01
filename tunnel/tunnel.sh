#!/usr/bin/env bash
# Persistent SSH tunnel that forwards remote dev-server ports from `moideen`
# to this Mac, so http://localhost:PORT reaches a server running on the box.
#
# Lazy, per-request: SSH opens the local listener once (at connect time), but
# only dials the remote port when you actually hit localhost:PORT. So a port
# with nothing running on the server just refuses that one request; start the
# server later and the next request works with NO tunnel restart. We forward
# every port always: an idle forward costs only a local listening socket.
#
# Ports come from the `ports` file beside this script (one per line; `#`
# comments and blank lines ignored). A reconnect loop heals sleep/network drops
# (ssh keepalives make a dead link exit in ~9s); the launchd agent's KeepAlive
# is a backstop if the whole process is killed.
#
# Run manually to test:  ~/.config/tunnel/tunnel.sh
set -euo pipefail

HOST="${REMOTE_HOST:-moideen}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTS_FILE="${TUNNEL_PORTS_FILE:-$DIR/ports}"

[ -r "$PORTS_FILE" ] || { echo "tunnel: cannot read $PORTS_FILE" >&2; exit 1; }

# Build the -L flags from the ports file.
fwd=()
while read -r port _; do
  case "$port" in ''|\#*) continue ;; esac
  fwd+=(-L "${port}:localhost:${port}")
done < "$PORTS_FILE"

[ "${#fwd[@]}" -gt 0 ] || { echo "tunnel: no ports listed in $PORTS_FILE" >&2; exit 1; }

# -N no shell, -T no pty. ControlPath=none gives this tunnel its own dedicated
# connection, isolated from the panes' shared master (pane churn never disturbs
# the forwards, and vice versa). ExitOnForwardFailure stays off so one local
# port already in use (e.g. macOS AirPlay on 5000) drops just that one forward,
# not the whole tunnel.
while :; do
  ssh -N -T \
    -o ControlPath=none \
    -o ServerAliveInterval=3 -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=no \
    "${fwd[@]}" "$HOST" || true
  echo "[tunnel] link down, reconnecting in 2s..." >&2
  sleep 2
done
