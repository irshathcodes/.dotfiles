#!/usr/bin/env bash
# Remote Linux dev-box setup. Target: Ubuntu/Debian. Idempotent — re-run any time.
#
# On a fresh machine:
#   git clone https://github.com/irshathcodes/.dotfiles.git ~/.dotfiles
#   ~/.dotfiles/linux/bootstrap.sh
#   exec zsh && claude
#
# Secrets (SSH key, AWS, kubeconfig) are pasted in interactively near the end —
# copy them from Bitwarden when prompted. Re-runs skip secrets already in place;
# set FORCE_SECRETS=1 to overwrite them.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # repo/linux
DOTFILES="$(cd "$HERE/.." && pwd)"                      # repo root (shares init.lua)

have() { command -v "$1" >/dev/null 2>&1; }
log()  { printf '\n==> %s\n' "$*"; }

# ---- version pins (deliberate; bump by hand) --------------------------------
NVIM_VERSION="v0.11.7"   # stay on 0.11.x; do NOT auto-upgrade to 0.12
FZF_VERSION="0.73.1"     # need >= 0.48 for `fzf --zsh` (apt ships 0.44)
NVM_VERSION="v0.40.5"    # includes CVE-2026-10796 fix
NODE_VERSION="24"
PNPM_VERSION="10"        # pinned to 10.x deliberately (v11 exists); via npm

export DEBIAN_FRONTEND=noninteractive
mkdir -p "$HOME/.local/bin"

# Architecture tokens differ per project, so resolve them all once.
case "$(uname -m)" in
  x86_64|amd64)  NVIM_ARCH=x86_64; FZF_ARCH=amd64; AWS_ARCH=x86_64  ;;
  aarch64|arm64) NVIM_ARCH=arm64;  FZF_ARCH=arm64; AWS_ARCH=aarch64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------- apt packages
# Note: ripgrep, fd-find, tealdeer, zsh-autosuggestions live in the `universe`
# component (enabled by default on stock Ubuntu). On a minimal image first run:
#   sudo add-apt-repository universe
log "apt: base + cli tools"
sudo apt-get update -y
sudo apt-get install -y \
  zsh git curl wget unzip ca-certificates build-essential \
  ripgrep fd-find tealdeer jq zsh-autosuggestions

# apt names fd `fdfind` — shim it to `fd` on PATH.
have fdfind && ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"

# tealdeer ships the `tldr` command but needs its page cache fetched once.
have tldr && { log "tldr cache"; tldr --update || true; }

# ---------------------------------------------------------------- fzf (upstream)
# apt's fzf (0.44) predates `fzf --zsh` used by the shell config. Pin a release
# binary instead — single executable, no git clone, version-controlled.
if [[ "$("$HOME/.local/bin/fzf" --version 2>/dev/null | awk '{print $1}')" != "$FZF_VERSION" ]]; then
  log "fzf $FZF_VERSION"
  tmp="$(mktemp -d)"
  curl -fL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${FZF_ARCH}.tar.gz" -o "$tmp/fzf.tgz"
  tar -xzf "$tmp/fzf.tgz" -C "$HOME/.local/bin"   # extracts a bare `fzf` binary
  chmod +x "$HOME/.local/bin/fzf"
  rm -rf "$tmp"
fi

# ---------------------------------------------------------------- neovim (0.11.x)
if [[ ! -x "$HOME/.local/nvim/bin/nvim" ]]; then
  log "neovim $NVIM_VERSION"
  tmp="$(mktemp -d)"
  curl -fL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz" -o "$tmp/nvim.tgz"
  mkdir -p "$HOME/.local/nvim"
  tar -xzf "$tmp/nvim.tgz" -C "$HOME/.local/nvim" --strip-components=1
  rm -rf "$tmp"
fi
[[ -x "$HOME/.local/nvim/bin/nvim" ]] && ln -sf "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"

# ---------------------------------------------------------------- gh (official repo)
if ! have gh; then
  log "gh (GitHub CLI)"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y gh
fi

# ---------------------------------------------------------------- docker
# Official apt repo (deb822 keyring). NOT the docker.io package, NOT get.docker.com.
if ! have docker; then
  log "docker engine + compose"
  . /etc/os-release
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y "$pkg" 2>/dev/null || true
  done
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/${ID}
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
# Run docker without sudo (takes effect on next login) + ensure the daemon is up.
sudo groupadd -f docker
sudo usermod -aG docker "$USER"
have systemctl && sudo systemctl enable --now docker.service containerd.service 2>/dev/null || true

# ---------------------------------------------------------------- aws cli v2
# Official zip installer (apt's awscli is v1/stale). --update makes re-runs safe.
log "aws cli v2"
tmp="$(mktemp -d)"
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "$tmp/awscliv2.zip"
unzip -q -o "$tmp/awscliv2.zip" -d "$tmp"
if have aws; then
  sudo "$tmp/aws/install" --update
else
  sudo "$tmp/aws/install"
fi
rm -rf "$tmp"

# ---------------------------------------------------------------- kubectl
# Direct binary from dl.k8s.io with checksum verify (the old apt repo is dead;
# a binary suits a box that talks to clusters of differing versions).
if ! have kubectl; then
  log "kubectl (latest stable)"
  karch="$(dpkg --print-architecture)"
  kver="$(curl -fL -s https://dl.k8s.io/release/stable.txt)"
  tmp="$(mktemp -d)"
  curl -fL -o "$tmp/kubectl"        "https://dl.k8s.io/release/${kver}/bin/linux/${karch}/kubectl"
  curl -fL -o "$tmp/kubectl.sha256" "https://dl.k8s.io/release/${kver}/bin/linux/${karch}/kubectl.sha256"
  echo "$(cat "$tmp/kubectl.sha256")  $tmp/kubectl" | sha256sum --check --status \
    || { echo "kubectl checksum FAILED" >&2; exit 1; }
  sudo install -o root -g root -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl
  rm -rf "$tmp"
fi

# ---------------------------------------------------------------- runtimes
# nvm + node, default pinned to $NODE_VERSION. PROFILE=/dev/null: don't edit our rc.
if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
  log "nvm $NVM_VERSION"
  PROFILE=/dev/null bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
fi
export NVM_DIR="$HOME/.nvm"
set +u; . "$NVM_DIR/nvm.sh"          # nvm.sh trips `set -u`; relax around it
log "node $NODE_VERSION (default)"
nvm install "$NODE_VERSION"
# Write a concrete vX.Y.Z into alias/default so the .zshrc fast-path resolves a
# real dir under versions/node/. Abort if the install didn't produce a version.
node_ver="$(nvm version "$NODE_VERSION")" || true   # don't let exit-3 (N/A) trip set -e
case "$node_ver" in
  v[0-9]*) nvm alias default "$node_ver" ;;
  *) echo "nvm: node $NODE_VERSION install failed (got '$node_ver')" >&2; exit 1 ;;
esac
nvm use default >/dev/null 2>&1 || true
set -u

# pnpm — pinned to v$PNPM_VERSION (latest matching), installed via npm.
log "pnpm $PNPM_VERSION"
npm install -g "pnpm@$PNPM_VERSION"

# ---------------------------------------------------------------- rust (rustup)
# Toolchain for the rust_analyzer + clippy setup in init.lua. Default profile
# includes clippy + rustfmt. --no-modify-path: we add ~/.cargo/bin in zshrc.
if [[ ! -x "$HOME/.cargo/bin/cargo" ]]; then
  log "rust (rustup)"
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile default
fi

# ---------------------------------------------------------------- Claude Code
# Native installer (Anthropic's recommended method): drops the launcher at
# ~/.local/bin/claude (already on PATH via zshrc), versioned binaries under
# ~/.local/share/claude, and auto-updates in the background. Default channel is
# `latest` (append `-s stable` for the ~1-week-delayed stable channel). The npm
# package is the same binary but won't auto-update.
[[ -x "$HOME/.local/bin/claude" ]] || { log "Claude Code (native installer)"; curl -fsSL https://claude.ai/install.sh | bash; }

# ---------------------------------------------------------------- link config
log "linking config"
ln -sf "$HERE/zshrc"               "$HOME/.zshrc"
ln -sf "$HERE/zsh_aliases"         "$HOME/.zsh_aliases"
ln -sf "$HERE/gitconfig"           "$HOME/.gitconfig"
mkdir -p "$HOME/.config/nvim" "$HOME/.config/git"
ln -sf "$DOTFILES/init.lua"        "$HOME/.config/nvim/init.lua"
ln -sf "$DOTFILES/lazy-lock.json"  "$HOME/.config/nvim/lazy-lock.json"
ln -sf "$DOTFILES/git/ignore"      "$HOME/.config/git/ignore"

# Claude config dir
mkdir -p "$HOME/.claude"

# Secrets file (sourced by zshrc); create from template if absent.
if [[ ! -f "$DOTFILES/.env" && -f "$DOTFILES/.env.example" ]]; then
  cp "$DOTFILES/.env.example" "$DOTFILES/.env"; chmod 600 "$DOTFILES/.env"
  echo "created $DOTFILES/.env from template — fill in real values"
fi

# ---------------------------------------------------------------- secrets (paste)
# Copy each from Bitwarden when prompted. Existing non-empty files are kept
# (FORCE_SECRETS=1 to replace). Needs a real terminal.
paste_secret() {                    # $1 dest  $2 mode  $3 label
  local dest="$1" mode="$2" label="$3" tmp
  if [[ -s "$dest" && "${FORCE_SECRETS:-0}" != 1 ]]; then
    echo "  $label: already present ($dest) — skip (FORCE_SECRETS=1 to replace)"
    return 0
  fi
  echo
  echo "  >>> Paste $label, then ENTER and Ctrl-D on a blank line (empty = skip):"
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp)"
  ( umask 077; cat > "$tmp" )       # verbatim bytes; private from creation
  if [[ ! -s "$tmp" ]]; then echo "  (nothing pasted — skipped $label)"; rm -f "$tmp"; return 0; fi
  [[ -n "$(tail -c1 "$tmp")" ]] && echo >> "$tmp"   # force trailing newline (OpenSSH needs it)
  mv "$tmp" "$dest"; chmod "$mode" "$dest"
  echo "  wrote $dest ($(wc -l < "$dest" | tr -d ' ') lines)"
}

if [[ -t 0 ]]; then
  log "restore secrets (paste from Bitwarden)"

  # GitHub SSH key
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  paste_secret "$HOME/.ssh/id_ed25519" 600 "GitHub SSH private key"
  if [[ -s "$HOME/.ssh/id_ed25519" ]]; then
    # derive the public key (skips quietly if the key is passphrase-protected)
    [[ -f "$HOME/.ssh/id_ed25519.pub" ]] \
      || ssh-keygen -y -f "$HOME/.ssh/id_ed25519" > "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
    [[ -f "$HOME/.ssh/id_ed25519.pub" ]] && chmod 644 "$HOME/.ssh/id_ed25519.pub"

    if ! grep -qi "^Host github.com" "$HOME/.ssh/config" 2>/dev/null; then
      cat >> "$HOME/.ssh/config" <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
EOF
      chmod 600 "$HOME/.ssh/config"
    fi

    # Pin GitHub's published ed25519 host key (safer than blind ssh-keyscan).
    if ! grep -q "github.com ssh-ed25519" "$HOME/.ssh/known_hosts" 2>/dev/null; then
      echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" >> "$HOME/.ssh/known_hosts"
      chmod 644 "$HOME/.ssh/known_hosts"
    fi

    echo "  testing GitHub auth..."
    ssh_out="$(ssh -T git@github.com 2>&1 || true)"
    if printf '%s' "$ssh_out" | grep -q "successfully authenticated"; then
      echo "  GitHub SSH OK"
    else
      echo "  GitHub SSH not verified — add the public key to GitHub, or the key is passphrase-protected"
    fi
  fi

  # AWS
  paste_secret "$HOME/.aws/credentials" 600 "AWS credentials (~/.aws/credentials)"
  paste_secret "$HOME/.aws/config"      600 "AWS config (~/.aws/config)"
  [[ -d "$HOME/.aws" ]] && chmod 700 "$HOME/.aws"

  # kubeconfig
  paste_secret "$HOME/.kube/config" 600 "kubeconfig (~/.kube/config)"
  [[ -d "$HOME/.kube" ]] && chmod 700 "$HOME/.kube"
else
  echo "secrets restore skipped (not a terminal) — re-run interactively to paste secrets"
fi

# ---------------------------------------------------------------- default shell
if [[ "${SHELL:-}" != *zsh ]]; then
  log "default shell -> zsh (may prompt for your password)"
  chsh -s "$(command -v zsh)" "$USER" || echo "chsh failed; run manually: chsh -s \$(command -v zsh)"
fi

cat <<'EOF'

Done. Next:
  exec zsh              # start the configured shell
  claude                # log in (auth is per-machine)
  gh auth login         # if you didn't restore an SSH key / want gh API access
  newgrp docker         # use docker without sudo now (or just re-login over SSH)

Deferred: zmx + mosh for session persistence.
EOF
