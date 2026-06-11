# pi coding-harness config

Version-controlled config for the [`pi`](https://pi) coding agent. The real
config lives in `~/.pi/agent`; the shareable parts are symlinked here so nothing
is lost across machines.

## Install

Run the root dotfiles installer (it handles the pi symlinks too):

```sh
cd ~/.dotfiles && ./install.sh
```

This symlinks the files below into `~/.pi/agent` (backing up anything in the way)
and bootstraps `~/.dotfiles/.env` from the example if missing.

## What's tracked

| Path                | Symlinked into `~/.pi/agent` | Notes |
|---------------------|------------------------------|-------|
| `agent/settings.json` | ✅ | core settings, enabled models, packages, extensions |
| `agent/mcp.json`      | ✅ | MCP servers; secrets via `${VAR}` interpolation |
| `agent/models.json`   | ✅ | provider/model defs (local Ollama) |
| `agent/extensions/`   | ✅ | custom TS extensions |
| `agent/docs/`         | ✅ | notes/docs |

## What's intentionally NOT tracked (stays local per machine)

- `auth.json` — OAuth tokens (Anthropic, Codex). **Never commit.**
- `trust.json`, `mcp-cache.json`, `run-history.jsonl`, `sessions/`,
  `context-mode/`, `todos/` — runtime/cache/state.
- `npm/` — auto-rebuilt by `pi` from `settings.json` `packages` on next run.

## Secrets

This repo is **public**, so secret values never get committed.

All secrets live in a single file at the dotfiles root:

- `~/.dotfiles/.env.example` — committed template.
- `~/.dotfiles/.env` — real values, **gitignored**, sourced by `.zshrc`.

`pi`'s MCP adapter interpolates `${VAR}` / `$env:VAR` in `mcp.json` from the
environment, so the Jira/Confluence tokens stay in `.env` only.

`.zshrc` contains:

```sh
[[ -f ~/.dotfiles/.env ]] && source ~/.dotfiles/.env
```

## New machine

```sh
git clone git@github.com:irshathcodes/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
cp .env.example .env && chmod 600 .env   # then fill in real tokens
# log in once so pi writes ~/.pi/agent/auth.json
```
