# dotfiles

Personal macOS dotfiles. Config lives here and is symlinked into place by
`install.sh`. Secrets are kept out of git.

## Install

```sh
git clone git@github.com:irshathcodes/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
cp .env.example .env && chmod 600 .env   # then fill in real secrets
```

`install.sh` is idempotent — re-run it any time. It backs up anything real that's
in the way before creating a symlink.

## What's here

| Path                      | Symlinked to                          |
|---------------------------|---------------------------------------|
| `.zshrc`                  | `~/.zshrc`                            |
| `.zsh_aliases`            | `~/.zsh_aliases`                     |
| `.gitconfig`              | `~/.gitconfig`                       |
| `kitty/`                  | `~/.config/kitty`                    |
| `karabiner-elements.json` | `~/.config/karabiner/karabiner.json` |
| `pi/agent/*`              | `~/.pi/agent/*` (see `pi/README.md`) |
| `init.lua`, `lazy-lock.json` | Neovim config (not auto-symlinked) |

## Secrets

The repo is **public**, so secrets never get committed.

- All secrets live in one file: `.env` (gitignored, `chmod 600`).
- `.env.example` is the committed template — copy it to `.env` and fill in values.
- `.zshrc` sources `.env` automatically, so tools (e.g. `pi`'s `mcp.json`
  `${VAR}` interpolation) can read them.

See [`pi/README.md`](pi/README.md) for details on the `pi` coding-agent config
and which of its files stay local per machine (auth tokens, runtime/cache).
