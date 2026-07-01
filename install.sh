#!/usr/bin/env bash
# Dotfiles installer — idempotent. Symlinks config into place and bootstraps .env.
#
# Usage: ./install.sh
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# symlink <src-relative-to-dotfiles> <absolute-dst>
symlink() {
  local src="$DOTFILES/$1"
  local dst="$2"

  [[ -e "$src" ]] || { echo "skip (missing in repo): $1"; return; }

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    echo "ok:   $dst"
    return
  fi

  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" || -L "$dst" ]]; then
    local backup="$dst.backup.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$backup"
    echo "moved existing -> $backup"
  fi

  ln -s "$src" "$dst"
  echo "link: $dst -> $src"
}

echo "==> home dotfiles"
symlink ".zshrc"        "$HOME/.zshrc"
symlink ".zsh_aliases"  "$HOME/.zsh_aliases"
symlink ".gitconfig"    "$HOME/.gitconfig"

echo "==> kitty"
symlink "kitty"         "$HOME/.config/kitty"
# Seed the per-project kitty session state (default layouts) if missing, so the
# native `cmd+j <letter>` goto_session always has a file to open. Idempotent;
# pure local file writes (no kitty/ssh needed). Live layouts auto-update after.
# `if` (not `&&/||`) so a real failure surfaces loudly instead of being masked
# by a trailing echo that always succeeds under `set -e`.
if "$DOTFILES/kitty/kittymux.sh" seed-all; then
  echo "seed: kitty session state ready"
else
  echo "WARNING: kittymux seed-all failed; run '~/.config/kitty/kittymux.sh seed-all' manually" >&2
fi

echo "==> moideen dev-server tunnel (launchd)"
# A single persistent background SSH tunnel forwarding remote dev-server ports
# to this Mac (see tunnel/tunnel.sh). launchd auto-starts it at login and
# restarts it if the process dies. The plist needs an absolute path to the
# script (launchd does NOT expand ~), so we render it from a template.
symlink "tunnel" "$HOME/.config/tunnel"
TUNNEL_LABEL="com.irshath.moideen-tunnel"
TUNNEL_PLIST="$HOME/Library/LaunchAgents/$TUNNEL_LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__TUNNEL_SH__|$HOME/.config/tunnel/tunnel.sh|g" \
  "$DOTFILES/tunnel/$TUNNEL_LABEL.plist.template" > "$TUNNEL_PLIST"
# Reload cleanly: bootout any old instance (ignore "not loaded") then bootstrap.
launchctl bootout "gui/$(id -u)/$TUNNEL_LABEL" 2>/dev/null || true
if launchctl bootstrap "gui/$(id -u)" "$TUNNEL_PLIST" 2>/dev/null; then
  echo "tunnel: launchd agent loaded (log: /tmp/moideen-tunnel.log)"
else
  echo "WARNING: launchctl bootstrap failed; load manually with:" >&2
  echo "  launchctl bootstrap gui/\$(id -u) $TUNNEL_PLIST" >&2
fi

echo "==> karabiner"
symlink "karabiner-elements.json" "$HOME/.config/karabiner/karabiner.json"

echo "==> claude code hooks (settings.json stays hand-managed; it holds local keys)"
symlink "claude/hooks/agent-panel-state.py" "$HOME/.claude/hooks/agent-panel-state.py"

echo "==> neovim"
symlink "init.lua"       "$HOME/.config/nvim/init.lua"
symlink "lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"

echo "==> git global ignore"
symlink "git/ignore"    "$HOME/.config/git/ignore"

echo "==> pi coding agent (shareable config only; secrets/runtime stay local)"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
for name in settings.json mcp.json models.json extensions docs; do
  symlink "pi/agent/$name" "$PI_DIR/$name"
done

echo "==> secrets"
if [[ ! -f "$DOTFILES/.env" ]]; then
  cp "$DOTFILES/.env.example" "$DOTFILES/.env"
  chmod 600 "$DOTFILES/.env"
  echo "Created $DOTFILES/.env from example — fill in real values."
else
  chmod 600 "$DOTFILES/.env"
  echo "ok:   $DOTFILES/.env (already present)"
fi

cat <<EOF

Done.
- Secrets live in $DOTFILES/.env (gitignored). .zshrc sources it automatically.
- 'pi' rebuilds ~/.pi/agent/npm from settings.json 'packages' on next run.
- auth.json (OAuth tokens) stays local per machine — log in once with pi.
EOF
