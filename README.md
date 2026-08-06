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
| `init.lua`, `lazy-lock.json` | `~/.config/nvim/`                  |
| `git/ignore`              | `~/.config/git/ignore` (global gitignore) |
| `hunk/config.toml`        | `~/.config/hunk/config.toml`         |

`kitty/sessions/*.kitty-session` are templates, not symlinks: `install.sh` copies
any that are missing into `~/.local/state/kitty/sessions/`, which is what kitty
actually loads. `cmd+shift+s` saves the live layout over the copy there, so
rearranging tabs never dirties this repo.

## Sessions

`cmd+j` is the leader for switching sessions, all local to this Mac:

| Key            | Session                        |
|----------------|--------------------------------|
| `cmd+j` `b`    | buildkit (`~/projects/buildkit`) |
| `cmd+j` `u`    | ui                             |
| `cmd+j` `d`    | default (`~`)                  |
| `cmd+j` `[`    | previous session               |
| `cmd+j` `/`    | fuzzy-pick an open session     |
| `cmd+j` `o`    | new session (project or scratch) |

Each project session is 4 tabs: nvim and claude (stacked), a server pane and a
shell (grid). `cmd+shift+s` persists the current tabs/splits/layouts/cwds — and
the programs running in them — back to the session file.

## Secrets

The repo is **public**, so secrets never get committed.

- All secrets live in one file: `.env` (gitignored, `chmod 600`).
- `.env.example` is the committed template — copy it to `.env` and fill in values.
- `.zshrc` sources `.env` automatically, so any tool that interpolates `${VAR}`
  can read them.
