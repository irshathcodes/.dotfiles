# Linux dev-box setup

Bootstraps a remote Ubuntu/Debian machine into a ready-to-use development
environment for working with Claude Code over SSH. Run once on a fresh box and
everything just works. Separate from the repo-root macOS config (which is set up
by hand).

## Use

```sh
# on the remote machine
git clone https://github.com/irshathcodes/.dotfiles.git ~/.dotfiles
~/.dotfiles/linux/bootstrap.sh
# (optional) fill in secrets, then:
exec zsh
claude    # log in (auth is per-machine)
```

`bootstrap.sh` is idempotent — re-run any time. Clone to `~/.dotfiles` (the shell
config sources `~/.dotfiles/.env`).

## What it installs

- **Shell:** zsh (set as default) + autosuggestions, fast git prompt, fzf, history
- **CLI:** ripgrep, fd, fzf (pinned), neovim (pinned 0.11.x), gh, tldr (tealdeer), jq
- **Infra:** docker + compose, aws cli v2, kubectl
- **Runtimes:** node 24 (nvm, lazy-loaded), pnpm 10, rust (rustup)
- **Claude Code**
- **Session persistence:** `zmx` (pinned) + the `cs` resolver, so nvim/claude/
  dev-servers survive SSH drops and reboots. Also raises sshd `MaxSessions` (many
  kitty panes share one connection) and enables linger (both need sudo).

## Secrets

Near the end, bootstrap prompts you to paste your secrets — copy each from
Bitwarden, paste, then Ctrl-D on a blank line (empty input skips one):

| Secret              | Restored to          | Notes                                  |
|---------------------|----------------------|----------------------------------------|
| GitHub SSH key      | `~/.ssh/id_ed25519`  | `.pub` derived, host key pinned, tested |
| AWS credentials     | `~/.aws/credentials` | + `~/.aws/config`                      |
| kubeconfig          | `~/.kube/config`     | `kuat`/`ksand`/`kprod` contexts        |

Files already present are kept on re-runs; `FORCE_SECRETS=1 ~/.dotfiles/linux/bootstrap.sh`
to replace them. Docker access without sudo needs one re-login after the first run.

## What it links

| Source (in repo)             | Linked to              |
|------------------------------|------------------------|
| `linux/zshenv`               | `~/.zshenv`            |
| `linux/zshrc`                | `~/.zshrc`             |
| `linux/zsh_aliases`          | `~/.zsh_aliases`       |
| `linux/gitconfig`            | `~/.gitconfig`         |
| `init.lua`, `lazy-lock.json` | `~/.config/nvim/`      |
| `git/ignore`                 | `~/.config/git/ignore` |
| `linux/cs/cs`                | `~/.local/bin/cs`      |
| `linux/cs/hook.zsh`          | `~/.config/cs/hook.zsh` |
| `linux/cs/projects`          | `~/.config/cs/projects` |

The neovim config (`init.lua`) is shared with the macOS setup at the repo root.
The `cs` project registry (`linux/cs/projects`) is shared across machines and
edited in-repo; `cs` tolerates a project whose directory doesn't exist locally.
